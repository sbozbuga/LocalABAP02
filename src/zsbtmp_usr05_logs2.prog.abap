*&---------------------------------------------------------------------*
*& Report ZSBTMP_USR05_LOGS2 - USR05 Change Logs Reader
*&---------------------------------------------------------------------*
*& Modernized & Consolidated DBTABLOG Reader for USR05 changes
*& Optimized Static Version (Zero Dynamic DDIC Calls)
*&---------------------------------------------------------------------*
REPORT zsbtmp_usr05_logs2.
TABLES: dbtablog, usr05.

TYPE-POOLS: icon.

*---------------------------------------------------------------------*
* GLOBAL TYPES
*---------------------------------------------------------------------*
TYPES: ty_bname_range  TYPE RANGE OF usr05-bname,
       ty_logdat_range TYPE RANGE OF dbtablog-logdate,
       ty_usera_range  TYPE RANGE OF dbtablog-username,
       ty_tcode_range  TYPE RANGE OF dbtablog-tcode,
       ty_optype_range TYPE RANGE OF dbtablog-optype.

TYPES: ty_dbtablog TYPE STANDARD TABLE OF dbtablog WITH DEFAULT KEY.

TYPES: BEGIN OF ty_shared_record,
         s_bname  TYPE ty_bname_range,
         s_logdat TYPE ty_logdat_range,
         s_usera  TYPE ty_usera_range,
         s_tcode  TYPE ty_tcode_range,
         s_optype TYPE ty_optype_range,
         p_real   TYPE abap_bool,
       END OF ty_shared_record.

TYPES: BEGIN OF ty_task_input,
         dblog  TYPE ty_dbtablog,
         shared TYPE ty_shared_record,
       END OF ty_task_input.

TYPES: BEGIN OF ty_xw_cd_usr05,
         bname TYPE usr05-bname.
         INCLUDE TYPE txw_cd_dbtablog.
         INCLUDE TYPE txw_cd_gen.
TYPES: END OF ty_xw_cd_usr05.

TYPES: BEGIN OF ty_output.
         INCLUDE TYPE ty_xw_cd_usr05.
TYPES:   icon  TYPE icon_d,
         color TYPE lvc_t_scol,
       END OF ty_output.

*---------------------------------------------------------------------*
* SELECTION SCREEN
*---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
SELECT-OPTIONS: s_bname FOR dbtablog-username MATCHCODE OBJECT user_logon,
                s_logdat FOR dbtablog-logdate.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-b02.
DATA: gv_usera  TYPE dbtablog-username,
      gv_tcode  TYPE dbtablog-tcode,
      gv_optype TYPE dbtablog-optype.
SELECT-OPTIONS: s_usera  FOR gv_usera,
                s_tcode  FOR gv_tcode,
                s_optype FOR gv_optype DEFAULT 'U'.
PARAMETERS p_real AS CHECKBOX DEFAULT abap_true.
SELECTION-SCREEN END OF BLOCK b02.

INITIALIZATION.
  s_logdat[] = VALUE #( ( sign = 'I' option = 'EQ'
                           low = sy-datum - 10
                          high = sy-datum ) ).

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
* LCL_PARALLEL_PROCESSOR
*---------------------------------------------------------------------*
CLASS lcl_parallel_processor DEFINITION INHERITING FROM cl_abap_parallel FINAL.
  PUBLIC SECTION.
    METHODS: do REDEFINITION.

  PRIVATE SECTION.
    METHODS:
      process_log_entry
        IMPORTING
          is_dblog    TYPE dbtablog
          id_tabix    TYPE i
          it_dbtablog TYPE ty_dbtablog
          is_current  TYPE lcl_usr05_log_decoder=>ty_usr05_data
          it_bname    TYPE ty_bname_range
          it_usera    TYPE ty_usera_range
          it_tcode    TYPE ty_tcode_range
          it_optype   TYPE ty_optype_range
          iv_real     TYPE abap_bool
        RETURNING
          VALUE(rs_output) TYPE ty_output,
      get_next_parva
        IMPORTING
          is_dbtablog   TYPE dbtablog
          id_tabix_next TYPE i
          id_bname      TYPE usr05-bname
          id_parid      TYPE usr05-parid
          it_dbtablog   TYPE ty_dbtablog
        RETURNING
          VALUE(rv_parva) TYPE usr05-parva.
ENDCLASS.

*---------------------------------------------------------------------*
* LCL_REPORT
*---------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      run.

  PRIVATE SECTION.
    CLASS-DATA:
      mt_output TYPE STANDARD TABLE OF ty_output.

    CLASS-METHODS:
      get_data,
      display_alv.
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
      DATA(lv_rc) = sy-subrc.
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
* LCL_PARALLEL_PROCESSOR IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_parallel_processor IMPLEMENTATION.

  METHOD do.
    DATA: ls_task_input TYPE ty_task_input,
          lt_output     TYPE STANDARD TABLE OF ty_output.

    IMPORT buffer_task = ls_task_input FROM DATA BUFFER p_in.

    LOOP AT ls_task_input-dblog ASSIGNING FIELD-SYMBOL(<ls_dblog>).
      " 1. Fast filters on the record before decoding (to avoid unnecessary decoding)
      IF <ls_dblog>-logdate NOT IN ls_task_input-shared-s_logdat.
        CONTINUE.
      ENDIF.
      IF <ls_dblog>-username NOT IN ls_task_input-shared-s_usera.
        CONTINUE.
      ENDIF.
      IF <ls_dblog>-tcode NOT IN ls_task_input-shared-s_tcode.
        CONTINUE.
      ENDIF.
      IF <ls_dblog>-optype NOT IN ls_task_input-shared-s_optype.
        CONTINUE.
      ENDIF.

      " 2. Filter on target user (bname) from logkey
      DATA(ls_current) = lcl_usr05_log_decoder=>decode_log( <ls_dblog> ).
      IF ls_current-bname NOT IN ls_task_input-shared-s_bname.
        CONTINUE.
      ENDIF.

      DATA(ls_output) = process_log_entry(
        is_dblog    = <ls_dblog>
        id_tabix    = sy-tabix
        it_dbtablog = ls_task_input-dblog
        is_current  = ls_current
        it_bname    = ls_task_input-shared-s_bname
        it_usera    = ls_task_input-shared-s_usera
        it_tcode    = ls_task_input-shared-s_tcode
        it_optype   = ls_task_input-shared-s_optype
        iv_real     = ls_task_input-shared-p_real ).

      IF ls_output-bname IS NOT INITIAL.
        APPEND ls_output TO lt_output.
      ENDIF.
    ENDLOOP.

    EXPORT buffer_result = lt_output TO DATA BUFFER p_out.
  ENDMETHOD.

  METHOD process_log_entry.
    CLEAR rs_output.

    " Populate generic and key fields via CORRESPONDING
    rs_output = CORRESPONDING #( is_dblog ).
    rs_output-bname     = is_current-bname.
    rs_output-username  = is_dblog-username.
    rs_output-udate     = is_dblog-logdate.
    rs_output-utime     = is_dblog-logtime.
    rs_output-tcode     = is_dblog-tcode.
    rs_output-chngind   = is_dblog-optype.
    rs_output-langu     = is_dblog-language.

    " Format tabkey
    DATA(ld_key_len) = strlen( is_dblog-logkey ).
    IF ld_key_len <= 70.
      rs_output-tabkey = is_dblog-logkey.
    ELSE.
      rs_output-tabkey = |{ is_dblog-logkey(69) }*|.
    ENDIF.

    " Specific field being changed
    rs_output-fname  = 'PARVA'.
    rs_output-ftext  = 'Parameter value'.
    rs_output-outlen = 40.

    CASE is_dblog-optype.
      WHEN 'I'.
        rs_output-value_old = ''.
        rs_output-value_new = is_current-parva.
        rs_output-icon      = icon_create.
        APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO rs_output-color.

      WHEN 'D'.
        rs_output-value_old = is_current-parva.
        rs_output-value_new = ''.
        rs_output-icon      = icon_delete.
        APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 3 int = 1 ) ) TO rs_output-color.

      WHEN 'U'.
        rs_output-value_old = is_current-parva.
        rs_output-value_new = get_next_parva(
          is_dbtablog   = is_dblog
          id_tabix_next = id_tabix + 1
          id_bname      = is_current-bname
          id_parid      = is_current-parid
          it_dbtablog   = it_dbtablog ).
        rs_output-icon      = icon_change.

        IF iv_real = abap_true AND rs_output-value_old = rs_output-value_new.
          CLEAR rs_output.
          RETURN.
        ENDIF.

        IF rs_output-value_old <> rs_output-value_new.
          APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 6 int = 1 ) ) TO rs_output-color.
          APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO rs_output-color.
        ENDIF.

      WHEN OTHERS.
        RETURN.
    ENDCASE.
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

    DATA: lt_next_logs TYPE ty_dbtablog.

    " 2. Try next entry in database (retrieve strictly newer changes, up to 1 row)
    SELECT tabname logdate logtime logkey optype username tcode language dataln logdata versno
      FROM dbtablog
      INTO CORRESPONDING FIELDS OF TABLE lt_next_logs
      UP TO 1 ROWS
      WHERE tabname = is_dbtablog-tabname
        AND logkey  = is_dbtablog-logkey
        AND ( logdate > is_dbtablog-logdate OR ( logdate = is_dbtablog-logdate AND logtime > is_dbtablog-logtime ) )
      ORDER BY logdate ASCENDING logtime ASCENDING.
    IF sy-subrc = 0.
      READ TABLE lt_next_logs INTO DATA(ls_next_log) INDEX 1.
      IF sy-subrc = 0.
        DATA(ls_decoded_db) = lcl_usr05_log_decoder=>decode_log( ls_next_log ).
        rv_parva = ls_decoded_db-parva.
        RETURN.
      ENDIF.
    ENDIF.

    " 3. Fallback: use actual database table entry (filtering on both keys bname and parid)
    SELECT SINGLE parva FROM usr05
      INTO rv_parva
      WHERE bname = id_bname
        AND parid = id_parid.
    IF sy-subrc <> 0.
      CLEAR rv_parva.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*---------------------------------------------------------------------*
* LCL_REPORT IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_report IMPLEMENTATION.

  METHOD run.
    get_data( ).
    display_alv( ).
  ENDMETHOD.

  METHOD get_data.
    DATA: ld_cursor    TYPE cursor,
          lt_chunk     TYPE ty_dbtablog,
          lt_in_tab    TYPE cl_abap_parallel=>t_in_tab,
          lv_in_single TYPE xstring,
          lt_out_tab   TYPE cl_abap_parallel=>t_out_tab.

    " Retrieve logs matching criteria via OPEN CURSOR (exclusively using TAB hint for USR05)
    OPEN CURSOR ld_cursor FOR
      SELECT tabname logdate logtime logkey optype username tcode language dataln logdata versno
        FROM dbtablog
        WHERE tabname = 'USR05'
        ORDER BY logkey ASCENDING logdate ASCENDING logtime ASCENDING
        %_HINTS ORACLE 'INDEX("DBTABLOG" "DBTABLOG~TAB")' HDB 'INDEX("DBTABLOG" "DBTABLOG~TAB")'.

    DO.
      FETCH NEXT CURSOR ld_cursor INTO TABLE lt_chunk PACKAGE SIZE 20000.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      " In-memory pre-filtering to minimize parallel processing overhead
      DATA: lt_filtered TYPE ty_dbtablog.
      CLEAR lt_filtered.

      LOOP AT lt_chunk ASSIGNING FIELD-SYMBOL(<ls_dblog>).
        IF <ls_dblog>-logdate NOT IN s_logdat.
          CONTINUE.
        ENDIF.
        IF <ls_dblog>-username NOT IN s_usera.
          CONTINUE.
        ENDIF.
        IF <ls_dblog>-tcode NOT IN s_tcode.
          CONTINUE.
        ENDIF.
        IF <ls_dblog>-optype NOT IN s_optype.
          CONTINUE.
        ENDIF.

        " Fast decode of target user from logkey (mandt 3 chars + bname 12 chars)
        DATA: lv_bname TYPE usr05-bname.
        lv_bname = <ls_dblog>-logkey+3(12).
        IF lv_bname NOT IN s_bname.
          CONTINUE.
        ENDIF.

        APPEND <ls_dblog> TO lt_filtered.
      ENDLOOP.

      IF lt_filtered IS NOT INITIAL.
        DATA: ls_task_input TYPE ty_task_input.
        CLEAR ls_task_input.
        ls_task_input-dblog = lt_filtered.
        ls_task_input-shared-s_bname[]  = s_bname[].
        ls_task_input-shared-s_logdat[] = s_logdat[].
        ls_task_input-shared-s_usera[]  = s_usera[].
        ls_task_input-shared-s_tcode[]  = s_tcode[].
        ls_task_input-shared-s_optype[] = s_optype[].
        ls_task_input-shared-p_real     = p_real.

        EXPORT buffer_task = ls_task_input TO DATA BUFFER lv_in_single.
        APPEND lv_in_single TO lt_in_tab.
      ENDIF.
    ENDDO.
    CLOSE CURSOR ld_cursor.

    IF lt_in_tab IS NOT INITIAL.
      " Create the parallel execution task
      DATA(lo_parallel) = NEW lcl_parallel_processor( ).

      " Execute tasks in parallel
      lo_parallel->run(
        EXPORTING
          p_in_tab  = lt_in_tab
        IMPORTING
          p_out_tab = lt_out_tab ).

      " Collect and deserialize outputs
      LOOP AT lt_out_tab ASSIGNING FIELD-SYMBOL(<ls_out>).
        IF <ls_out>-message IS NOT INITIAL.
          CONTINUE.
        ENDIF.

        IF <ls_out>-result IS NOT INITIAL.
          DATA: lt_worker_output TYPE STANDARD TABLE OF ty_output.
          IMPORT buffer_result = lt_worker_output FROM DATA BUFFER <ls_out>-result.
          APPEND LINES OF lt_worker_output TO mt_output.
        ENDIF.
      ENDLOOP.
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

        " Hide unneeded columns
        DATA: lt_hide TYPE STANDARD TABLE OF salv_de_column WITH DEFAULT KEY.
        lt_hide = VALUE #( ( 'MANDT' )
                           ( 'TABNAME' )
                           ( 'TABKEY' )
                           ( 'FNAME' )
                           ( 'FTEXT' )
                           ( 'OUTLEN' )
                           ( 'VERSNO' )
                           ( 'COLOR' )
                           ( 'LOGID' )
                           ( 'PROGNAME' )
                           ( 'BNAME' )
                           ( 'CHANGENR' )
                           ( 'CHNGIND' ) ).
        LOOP AT lt_hide INTO DATA(lv_col).
          TRY.
              lo_cols->get_column( lv_col )->set_visible( abap_false ).
            CATCH cx_salv_not_found.
          ENDTRY.
        ENDLOOP.

        " Modernize column texts
        TRY.
            DATA: lo_col_table TYPE REF TO cl_salv_column_table.
            lo_col_table ?= lo_cols->get_column( 'ICON' ).
            lo_col_table->set_icon( abap_true ).
            lo_col_table->set_medium_text( 'Change Type' ).
          CATCH cx_salv_not_found.
        ENDTRY.

        " Enable standard toolbar functions
        lo_alv->get_functions( )->set_all( abap_true ).

        lo_alv->display( ).
      CATCH cx_salv_error.
        MESSAGE 'Error initializing ALV Display' TYPE 'E'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

