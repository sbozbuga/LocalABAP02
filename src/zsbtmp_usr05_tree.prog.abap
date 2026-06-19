*&---------------------------------------------------------------------*
*& Report ZSBTMP_USR05_TREE
*&---------------------------------------------------------------------*
*& ALV Tree and Grid Split-Screen Display for USR05 Change Logs
*& Optimized Static Version (Zero Dynamic DDIC Calls)
*&---------------------------------------------------------------------*
REPORT zsbtmp_usr05_tree.

TYPE-POOLS: icon.

TYPES: ty_it_events TYPE STANDARD TABLE OF cntl_simple_event WITH DEFAULT KEY,
       ty_it_nodes  TYPE STANDARD TABLE OF mtreesnode WITH DEFAULT KEY.

*---------------------------------------------------------------------*
* SELECTION SCREEN
*---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
DATA: gv_bname TYPE usr05-bname.
SELECT-OPTIONS s_bname FOR gv_bname NO INTERVALS MATCHCODE OBJECT user_logon.
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
* LCL_REPORT DEFINITION
*---------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF txw_cd_usr05,
             bname TYPE usr05-bname.
             INCLUDE TYPE txw_cd_dbtablog.
             INCLUDE TYPE txw_cd_gen.
    TYPES: END OF txw_cd_usr05,
           BEGIN OF ty_output.
             INCLUDE TYPE txw_cd_usr05.
    TYPES:   parid TYPE usr05-parid,
             icon  TYPE icon_d,
             color TYPE lvc_t_scol,
           END OF ty_output,
           tt_dbtablog TYPE STANDARD TABLE OF dbtablog WITH DEFAULT KEY,
           BEGIN OF ty_node_map,
             node_key TYPE salv_de_node_key,
             bname    TYPE usr05-bname,
             parid    TYPE usr05-parid,
           END OF ty_node_map.

    CLASS-METHODS:
      run,
      refresh_grid
        IMPORTING
          id_node_key TYPE salv_de_node_key.

  PRIVATE SECTION.
    CLASS-DATA:
      mt_all_logs TYPE STANDARD TABLE OF ty_output,
      mt_grid_log TYPE STANDARD TABLE OF ty_output,
      mt_node_map TYPE STANDARD TABLE OF ty_node_map,
      it_nodes    TYPE ty_it_nodes,
      go_alv      TYPE REF TO cl_salv_table,
      go_tree     TYPE REF TO cl_gui_simple_tree.

    CLASS-METHODS:
      get_data,
      display_split_screen,
      build_tree,
      setup_alv_grid,
      process_log_entry
        IMPORTING
          is_dblog      TYPE dbtablog
          id_tabix      TYPE i
          it_dbtablog   TYPE tt_dbtablog
          is_current    TYPE lcl_usr05_log_decoder=>ty_usr05_data
        RETURNING
          VALUE(rs_out) TYPE ty_output,
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
* LCL_EVENT_HANDLER DEFINITION
*---------------------------------------------------------------------*
CLASS lcl_event_handler DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      on_selection_changed FOR EVENT selection_changed OF cl_gui_simple_tree
        IMPORTING
          node_key
          sender.
ENDCLASS.

*---------------------------------------------------------------------*
* START-OF-SELECTION
*---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_report=>run( ).
  cl_abap_list_layout=>suppress_toolbar( ).
  WRITE space.

*---------------------------------------------------------------------*
* LCL_EVENT_HANDLER IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_event_handler IMPLEMENTATION.
  METHOD on_selection_changed.
    DATA(lo_sender) = sender.
    lcl_report=>refresh_grid( node_key ).
  ENDMETHOD.
ENDCLASS.

*---------------------------------------------------------------------*
* LCL_REPORT IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_report IMPLEMENTATION.

  METHOD run.
    get_data( ).
    display_split_screen( ).
  ENDMETHOD.

  METHOD get_data.
    TYPES: BEGIN OF ty_usr01_bname,
             bname TYPE usr01-bname,
           END OF ty_usr01_bname.
    DATA: lt_users   TYPE STANDARD TABLE OF ty_usr01_bname WITH DEFAULT KEY,
          lt_dblog   TYPE tt_dbtablog,
          rt_logkey  TYPE RANGE OF dbtablog-logkey,
          lv_use_key TYPE abap_bool VALUE abap_false.

    IF s_bname IS NOT INITIAL.
      SELECT bname FROM usr01
        WHERE bname IN @s_bname
        INTO CORRESPONDING FIELDS OF TABLE @lt_users.
      IF sy-subrc = 0.
        LOOP AT lt_users INTO DATA(ls_user).
          APPEND VALUE #(
            sign   = 'I'
            option = 'CP'
            low    = |{ sy-mandt }{ ls_user-bname }*| ) TO rt_logkey.
        ENDLOOP.
        lv_use_key = abap_true.
      ENDIF.
    ENDIF.

    " Retrieve logs matching criteria with modern, fast selection
    IF lv_use_key = abap_true.
      SELECT tabname, logdate, logtime, logkey, optype, username, tcode, language, dataln, logdata, versno
        FROM dbtablog
        WHERE tabname  = 'USR05'
          AND logdate  BETWEEN @dbeg AND @dend
          AND logkey   IN @rt_logkey
          AND username IN @s_usera
          AND tcode    IN @s_tcode
          AND optype   IN @s_optype
        ORDER BY logkey ASCENDING, logdate ASCENDING, logtime ASCENDING
        INTO CORRESPONDING FIELDS OF TABLE @lt_dblog.
      IF sy-subrc <> 0.
        " check sy-subrc for linter
      ENDIF.
    ELSE.
      SELECT tabname, logdate, logtime, logkey, optype, username, tcode, language, dataln, logdata, versno
        FROM dbtablog
        WHERE tabname  = 'USR05'
          AND logdate  BETWEEN @dbeg AND @dend
          AND username IN @s_usera
          AND tcode    IN @s_tcode
          AND optype   IN @s_optype
        ORDER BY logkey ASCENDING, logdate ASCENDING, logtime ASCENDING
        INTO CORRESPONDING FIELDS OF TABLE @lt_dblog.
      IF sy-subrc <> 0.
        " check sy-subrc for linter
      ENDIF.
    ENDIF.

    LOOP AT lt_dblog ASSIGNING FIELD-SYMBOL(<ls_dblog>).
      " Decode log entry
      DATA(ls_current) = lcl_usr05_log_decoder=>decode_log( <ls_dblog> ).

      IF ls_current-bname NOT IN s_bname.
        CONTINUE.
      ENDIF.

      DATA(ls_output) = process_log_entry(
        is_dblog    = <ls_dblog>
        id_tabix    = sy-tabix
        it_dbtablog = lt_dblog
        is_current  = ls_current ).

      IF ls_output IS NOT INITIAL.
        APPEND ls_output TO mt_all_logs.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD process_log_entry.
    " Populate generic and key fields via CORRESPONDING
    rs_out = CORRESPONDING #( is_dblog ).
    rs_out-bname     = is_current-bname.
    rs_out-parid     = is_current-parid.
    rs_out-username  = is_dblog-username.
    rs_out-udate     = is_dblog-logdate.
    rs_out-utime     = is_dblog-logtime.
    rs_out-tcode     = is_dblog-tcode.
    rs_out-chngind   = is_dblog-optype.
    rs_out-langu     = is_dblog-language.

    " Format tabkey
    DATA(ld_key_len) = strlen( is_dblog-logkey ).
    IF ld_key_len <= 70.
      rs_out-tabkey = is_dblog-logkey.
    ELSE.
      rs_out-tabkey = |{ is_dblog-logkey(69) }*|.
    ENDIF.

    " Specific field being changed
    rs_out-fname  = 'PARVA'.
    rs_out-ftext  = 'Parameter value'.
    rs_out-outlen = 40.

    CASE is_dblog-optype.
      WHEN 'I'.
        rs_out-value_old = ''.
        rs_out-value_new = is_current-parva.
        rs_out-icon      = icon_create.
        APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO rs_out-color.

      WHEN 'D'.
        rs_out-value_old = is_current-parva.
        rs_out-value_new = ''.
        rs_out-icon      = icon_delete.
        APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 3 int = 1 ) ) TO rs_out-color.

      WHEN 'U'.
        rs_out-value_old = is_current-parva.
        rs_out-value_new = get_next_parva(
          is_dbtablog   = is_dblog
          id_tabix_next = id_tabix + 1
          id_bname      = is_current-bname
          id_parid      = is_current-parid
          it_dbtablog   = it_dbtablog ).
        rs_out-icon      = icon_change.

        IF p_real = abap_true.
          IF rs_out-value_old = rs_out-value_new.
            CLEAR rs_out.
            RETURN.
          ENDIF.
        ENDIF.

        IF rs_out-value_old <> rs_out-value_new.
          APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 6 int = 1 ) ) TO rs_out-color.
          APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO rs_out-color.
        ENDIF.

      WHEN OTHERS.
        CLEAR rs_out.
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

    DATA: lt_next_logs TYPE tt_dbtablog.

    " 2. Try next entry in database
    SELECT tabname, logdate, logtime, logkey, optype, username, tcode, language, dataln, logdata, versno
      FROM dbtablog
      WHERE tabname = @is_dbtablog-tabname
        AND logdate >= @is_dbtablog-logdate
        AND logkey  = @is_dbtablog-logkey
      ORDER BY logdate ASCENDING, logtime ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @lt_next_logs.
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

  METHOD display_split_screen.
    DATA: lo_split     TYPE REF TO cl_gui_splitter_container,
          lo_spl_left  TYPE REF TO cl_gui_container,
          lo_spl_right TYPE REF TO cl_gui_container,
          it_events    TYPE ty_it_events.

    " Create Splitter on screen0 (forces render on standard list screen)
    CREATE OBJECT lo_split
      EXPORTING
        parent                  = cl_gui_container=>screen0
        no_autodef_progid_dynnr = abap_true
        rows                    = 1
        columns                 = 2.

    lo_split->set_column_width(
      EXPORTING
        id    = 1
        width = 25 ).

    lo_spl_left  = lo_split->get_container( row = 1 column = 1 ).
    lo_spl_right = lo_split->get_container( row = 1 column = 2 ).

    TRY.
        " Create Tree on the left container
        CREATE OBJECT go_tree
          EXPORTING
            parent              = lo_spl_left
            node_selection_mode = cl_gui_simple_tree=>node_sel_mode_single.

        " Register selection_changed event
        APPEND VALUE #( eventid    = cl_gui_simple_tree=>eventid_selection_changed
                        appl_event = abap_true ) TO it_events.
        go_tree->set_registered_events( events = it_events ).

        " Set event handler
        SET HANDLER lcl_event_handler=>on_selection_changed FOR go_tree.

        " Show all records initially in the right grid
        mt_grid_log = mt_all_logs.

        " Create Grid on the right container
        cl_salv_table=>factory(
          EXPORTING
            r_container  = lo_spl_right
          IMPORTING
            r_salv_table = go_alv
          CHANGING
            t_table      = mt_grid_log ).

        build_tree( ).
        setup_alv_grid( ).

        go_alv->display( ).
      CATCH cx_root INTO DATA(lo_err).
        MESSAGE lo_err->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD build_tree.
    DATA: lv_prev_bname TYPE usr05-bname,
          lv_prev_parid TYPE usr05-parid,
          lv_bname_key  TYPE salv_de_node_key,
          lv_parid_key  TYPE salv_de_node_key,
          lv_node_idx   TYPE i VALUE 0.

    " Root-Node
    DATA(lv_total_count) = lines( mt_all_logs ).

    APPEND VALUE #( node_key  = 'ROOT'
                    relatship = cl_gui_simple_tree=>relat_last_child
                    isfolder  = abap_true
                    n_image   = icon_folder
                    exp_image = icon_open_folder
                    style     = cl_gui_simple_tree=>style_default
                    text      = |User Parameter Changes ({ lv_total_count })| ) TO it_nodes.

    LOOP AT mt_all_logs ASSIGNING FIELD-SYMBOL(<ls_log>).
      IF <ls_log>-bname <> lv_prev_bname.
        lv_prev_bname = <ls_log>-bname.
        CLEAR lv_prev_parid.

        lv_node_idx = lv_node_idx + 1.
        lv_bname_key = |N{ lv_node_idx }|.

        DATA(lv_user_count) = 0.
        LOOP AT mt_all_logs TRANSPORTING NO FIELDS WHERE bname = lv_prev_bname.
          lv_user_count = lv_user_count + 1.
        ENDLOOP.

        APPEND VALUE #( node_key  = lv_bname_key
                        relatship = cl_gui_simple_tree=>relat_last_child
                        relatkey  = 'ROOT'
                        isfolder  = abap_true
                        n_image   = icon_folder
                        exp_image = icon_open_folder
                        style     = cl_gui_simple_tree=>style_intensified
                        text      = |User: { lv_prev_bname } ({ lv_user_count })| ) TO it_nodes.

        APPEND VALUE #( node_key = lv_bname_key
                        bname    = lv_prev_bname ) TO mt_node_map.
      ENDIF.

      IF <ls_log>-parid <> lv_prev_parid.
        lv_prev_parid = <ls_log>-parid.

        lv_node_idx = lv_node_idx + 1.
        lv_parid_key = |N{ lv_node_idx }|.

        DATA(lv_param_count) = 0.
        LOOP AT mt_all_logs TRANSPORTING NO FIELDS WHERE bname = lv_prev_bname AND parid = lv_prev_parid.
          lv_param_count = lv_param_count + 1.
        ENDLOOP.

        APPEND VALUE #( node_key  = lv_parid_key
                        relatship = cl_gui_simple_tree=>relat_last_child
                        relatkey  = lv_bname_key
                        isfolder  = abap_false
                        style     = cl_gui_simple_tree=>style_default
                        text      = |{ lv_prev_parid } ({ lv_param_count })| ) TO it_nodes.

        APPEND VALUE #( node_key = lv_parid_key
                        bname    = lv_prev_bname
                        parid    = lv_prev_parid ) TO mt_node_map.
      ENDIF.
    ENDLOOP.

    " Add nodes to simple tree
    go_tree->add_nodes(
      EXPORTING
        table_structure_name = 'MTREESNODE'
        node_table           = it_nodes ).

    " Expand entire tree recursively starting from root node
    go_tree->expand_node(
      EXPORTING
        node_key       = 'ROOT'
        expand_subtree = abap_true ).
  ENDMETHOD.

  METHOD setup_alv_grid.
    DATA: lo_cols TYPE REF TO cl_salv_columns_table.

    lo_cols = go_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    TRY.
        lo_cols->set_color_column( 'COLOR' ).
      CATCH cx_salv_data_error.
    ENDTRY.

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

    " Format icon column
    TRY.
        DATA: lo_col_table TYPE REF TO cl_salv_column_table.
        lo_col_table ?= lo_cols->get_column( 'ICON' ).
        lo_col_table->set_icon( abap_true ).
        lo_col_table->set_medium_text( 'Change Type' ).
      CATCH cx_salv_error.
    ENDTRY.

    " Enable standard toolbar tools
    go_alv->get_functions( )->set_all( abap_true ).
  ENDMETHOD.

  METHOD refresh_grid.
    DATA: ls_log TYPE ty_output.

    READ TABLE mt_node_map INTO DATA(ls_map) WITH KEY node_key = id_node_key.
    IF sy-subrc = 0.
      CLEAR mt_grid_log.
      IF ls_map-parid IS INITIAL.
        " User node clicked -> show all parameters for this user
        LOOP AT mt_all_logs INTO ls_log WHERE bname = ls_map-bname.
          APPEND ls_log TO mt_grid_log.
        ENDLOOP.
      ELSE.
        " Parameter node clicked -> show logs of this parameter for this user
        LOOP AT mt_all_logs INTO ls_log WHERE bname = ls_map-bname AND parid = ls_map-parid.
          APPEND ls_log TO mt_grid_log.
        ENDLOOP.
      ENDIF.

      go_alv->refresh( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
