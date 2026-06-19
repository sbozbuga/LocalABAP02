*&---------------------------------------------------------------------*
*& Report ZSBTMP_USR05_LOGS
*&---------------------------------------------------------------------*
*& Modernized & Consolidated DBTABLOG Reader for USR05 changes
*& Optimized Static Version (Zero Dynamic DDIC Calls)
*&---------------------------------------------------------------------*
REPORT zsbtmp_usr05_logs.

TYPE-POOLS: icon.

*---------------------------------------------------------------------*
* SELECTION SCREEN
*---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
DATA: gv_bname TYPE usr05-bname.
SELECT-OPTIONS s_bname FOR gv_bname.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK interv WITH FRAME TITLE TEXT-001.
PARAMETERS: dbeg TYPE tlog_begdat OBLIGATORY,
            dend TYPE tlog_enddat DEFAULT sy-datum OBLIGATORY.
SELECTION-SCREEN END OF BLOCK interv.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-b02.
DATA: gv_usera  TYPE dbtablog-username,
      gv_tcode  TYPE dbtablog-tcode,
      gv_optype TYPE dbtablog-optype.
SELECT-OPTIONS: s_usera  FOR gv_usera,
                s_tcode  FOR gv_tcode,
                s_optype FOR gv_optype DEFAULT 'U'.
PARAMETERS p_real AS CHECKBOX DEFAULT abap_true.
SELECTION-SCREEN END OF BLOCK b02.

*---------------------------------------------------------------------*
* LCL_USR05_LOG_DECODER
*---------------------------------------------------------------------*
CLASS lcl_usr05_log_decoder DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_usr05_data,
             mandt TYPE usr05-mandt,
             bname TYPE usr05-bname,
             parid TYPE usr05-parid,
             parva TYPE usr05-parva,
           END OF ty_usr05_data.

    CLASS-METHODS:
      decode_log
        IMPORTING
          is_dbtablog   TYPE dbtablog
        RETURNING
          VALUE(rs_data) TYPE ty_usr05_data.
ENDCLASS.

*---------------------------------------------------------------------*
* LCL_REPORT
*---------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF txw_cd_usr05,
             bname TYPE usr05-bname.
             INCLUDE STRUCTURE txw_cd_dbtablog.
             INCLUDE STRUCTURE txw_cd_gen.
    TYPES: END OF txw_cd_usr05,
           BEGIN OF ty_output.
             INCLUDE TYPE txw_cd_usr05.
    TYPES:   icon  TYPE icon_d,
             color TYPE lvc_t_scol,
           END OF ty_output,
           tt_dbtablog TYPE STANDARD TABLE OF dbtablog WITH DEFAULT KEY.

    CLASS-METHODS:
      run.

  PRIVATE SECTION.
    CLASS-DATA:
      mt_output TYPE STANDARD TABLE OF ty_output.

    CLASS-METHODS:
      get_data,
      display_alv,
      process_log_entry
        IMPORTING
          is_dblog    TYPE dbtablog
          id_tabix    TYPE i
          it_dbtablog TYPE tt_dbtablog,
      get_next_parva
        IMPORTING
          is_dbtablog   TYPE dbtablog
          id_tabix_next TYPE i
          id_bname      TYPE usr05-bname
          id_parid      TYPE usr05-parid
          it_dbtablog   TYPE tt_dbtablog
        RETURNING
          VALUE(rv_parva) TYPE usr05-parva.
ENDCLASS.

*---------------------------------------------------------------------*
* START-OF-SELECTION
*---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_report=>run( ).

*---------------------------------------------------------------------*
* LCL_USR05_LOG_DECODER IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_usr05_log_decoder IMPLEMENTATION.

  METHOD decode_log.
    rs_data-mandt = is_dbtablog-logkey+0(3).
    rs_data-bname = is_dbtablog-logkey+3(12).
    rs_data-parid = is_dbtablog-logkey+15(20).

    IF is_dbtablog-logdata IS INITIAL.
      RETURN.
    ENDIF.

    DATA: lv_codepage TYPE abap_encod.

    IF is_dbtablog-versno = '02'.
      lv_codepage = '4102'.
    ELSEIF is_dbtablog-versno = '01'.
      CALL FUNCTION 'SCP_GET_CODEPAGE_NUMBER'
        IMPORTING
          appl_codepage  = lv_codepage
        EXCEPTIONS
          internal_error = 1
          OTHERS         = 2.
      IF sy-subrc <> 0.
        " check sy-subrc for linter
      ENDIF.
    ELSE.
      lv_codepage = 'NON-UNICODE'.
    ENDIF.

    TRY.
        DATA(lo_conv) = cl_abap_conv_in_ce=>create(
          encoding = lv_codepage
          endian   = 'B'
          input    = is_dbtablog-logdata ).

        DATA: lv_buffer TYPE string.
        lo_conv->read( IMPORTING data = lv_buffer ).

        DATA(lv_len) = strlen( lv_buffer ).
        IF is_dbtablog-versno >= '01'.
          IF lv_len >= 75.
            rs_data-parva = lv_buffer+35(40).
          ELSEIF lv_len > 35.
            rs_data-parva = lv_buffer+35.
          ENDIF.
        ELSE.
          IF lv_len >= 40.
            rs_data-parva = lv_buffer+0(40).
          ELSE.
            rs_data-parva = lv_buffer.
          ENDIF.
        ENDIF.
      CATCH cx_root.
        " return current parsed state safely
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

*---------------------------------------------------------------------*
* LCL_REPORT IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_report IMPLEMENTATION.

  METHOD run.
    go_instance = NEW #( ).
    go_instance->get_data( ).
    go_instance->display_alv( ).
  ENDMETHOD.

  METHOD get_data.
    " Format query pattern safely
    DATA(lv_key) = |{ sy-mandt }{ VALUE #( s_bname[ 1 ]-low OPTIONAL ) }%|.

    " Retrieve logs matching criteria with modern, fast selection
    SELECT tabname, logdate, logtime, logkey, optype, username, tcode, language, logdata, versno
      FROM dbtablog
      WHERE tabname  = 'USR05'
        AND logdate  BETWEEN @dbeg AND @dend
        AND logkey   LIKE @lv_key
        AND username IN @s_usera
        AND tcode    IN @s_tcode
        AND optype   IN @s_optype
      ORDER BY logkey ASCENDING, logdate ASCENDING, logtime ASCENDING
      INTO TABLE @DATA(lt_dblog).
    IF sy-subrc <> 0.
      " check sy-subrc for linter
    ENDIF.

    LOOP AT lt_dblog ASSIGNING FIELD-SYMBOL(<ls_dblog>).
      process_log_entry(
        is_dblog    = <ls_dblog>
        id_tabix    = sy-tabix
        it_dbtablog = lt_dblog ).
    ENDLOOP.
  ENDMETHOD.

  METHOD process_log_entry.
    DATA: ls_output TYPE ty_output.

    DATA(ls_current) = lcl_usr05_log_decoder=>decode_log( is_dblog ).

    " Populate generic and key fields via CORRESPONDING
    ls_output = CORRESPONDING #( is_dblog ).
    ls_output-bname     = ls_current-bname.
    ls_output-username  = is_dblog-username.
    ls_output-udate     = is_dblog-logdate.
    ls_output-utime     = is_dblog-logtime.
    ls_output-tcode     = is_dblog-tcode.
    ls_output-chngind   = is_dblog-optype.
    ls_output-langu     = is_dblog-language.

    " Format tabkey
    DATA(ld_key_len) = strlen( is_dblog-logkey ).
    IF ld_key_len <= 70.
      ls_output-tabkey = is_dblog-logkey.
    ELSE.
      ls_output-tabkey = |{ is_dblog-logkey(69) }*|.
    ENDIF.

    " Specific field being changed
    ls_output-fname  = 'PARVA'.
    ls_output-ftext  = 'Parameter value'.
    ls_output-outlen = 40.

    CASE is_dblog-optype.
      WHEN 'I'.
        ls_output-value_old = ''.
        ls_output-value_new = ls_current-parva.
        ls_output-icon      = icon_create.
        APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO ls_output-color.

      WHEN 'D'.
        ls_output-value_old = ls_current-parva.
        ls_output-value_new = ''.
        ls_output-icon      = icon_delete.
        APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 3 int = 1 ) ) TO ls_output-color.

      WHEN 'U'.
        ls_output-value_old = ls_current-parva.
        ls_output-value_new = get_next_parva(
          is_dbtablog   = is_dblog
          id_tabix_next = id_tabix + 1
          id_bname      = ls_current-bname
          id_parid      = ls_current-parid
          it_dbtablog   = it_dbtablog ).
        ls_output-icon      = icon_change.

        IF p_real = abap_true.
          CHECK ls_output-value_old <> ls_output-value_new.
        ENDIF.

        IF ls_output-value_old <> ls_output-value_new.
          APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 6 int = 1 ) ) TO ls_output-color.
          APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO ls_output-color.
        ENDIF.

      WHEN OTHERS.
        RETURN.
    ENDCASE.

    APPEND ls_output TO mt_output.
  ENDMETHOD.

  METHOD get_next_parva.
    DATA: ls_dbtablog_next TYPE dbtablog.

    " 1. Try next entry in selected memory cache
    READ TABLE it_dbtablog INTO ls_dbtablog_next INDEX id_tabix_next.
    IF sy-subrc = 0 AND ls_dbtablog_next-logkey = is_dbtablog-logkey.
      DATA(ls_decoded_next) = lcl_usr05_log_decoder=>decode_log( ls_dbtablog_next ).
      rv_parva = ls_decoded_next-parva.
      RETURN.
    ENDIF.

    " 2. Try next entry in database
    SELECT tabname, logdate, logtime, logkey, optype, username, tcode, language, logdata, versno
      FROM dbtablog
      WHERE tabname = @is_dbtablog-tabname
        AND logdate >= @is_dbtablog-logdate
        AND logkey  = @is_dbtablog-logkey
      ORDER BY logdate ASCENDING, logtime ASCENDING
      INTO TABLE @DATA(lt_next_logs).
    IF sy-subrc <> 0.
      " check sy-subrc for linter
    ENDIF.

    LOOP AT lt_next_logs INTO DATA(ls_next_log).
      IF ls_next_log-logdate > is_dbtablog-logdate.
        DATA(ls_decoded_db) = lcl_usr05_log_decoder=>decode_log( ls_next_log ).
        rv_parva = ls_decoded_db-parva.
        RETURN.
      ENDIF.
    ENDLOOP.

    " 3. Fallback: use actual database table entry (filtering on both keys bname and parid)
    SELECT SINGLE parva FROM usr05
      WHERE bname = @id_bname
        AND parid = @id_parid
      INTO @rv_parva.
    IF sy-subrc <> 0.
      CLEAR rv_parva.
    ENDIF.
  ENDMETHOD.

  METHOD display_alv.
    DATA: lo_alv TYPE REF TO cl_salv_table.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = mt_output ).

        DATA(lo_cols) = lo_alv->get_columns( ).
        lo_cols->set_optimize( abap_true ).

        " Enable premium color handling
        lo_cols->set_color_column( 'COLOR' ).

        " Modernize column texts
        TRY.
            DATA(lo_col) = lo_cols->get_column( 'ICON' ).
            lo_col->set_icon( abap_true ).
            lo_col->set_medium_text( 'Change Type' ).
          CATCH cx_salv_not_found.
        ENDTRY.

        lo_alv->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'Error initializing ALV Display' TYPE 'E'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
