*&---------------------------------------------------------------------*
*& Report ZSBTMP_GEN_TREE - Generic Table Change Explorer
*&---------------------------------------------------------------------*
*& PURPOSE:
*&   An interactive utility to explore database table change logs for any
*&   table configured for logging in the SAP system. Displays changes in
*&   a split screen: a 2-level ALV Tree on the left (grouped by key)
*&   and a detailed ALV Grid of field-level changes on the right.
*&
*& DYNAMIC PROCESS FLOW:
*&   1. Metadata Analysis:
*&      Uses RTTI (cl_abap_structdescr) to dynamically retrieve the DDIC
*&      structure of the target table (P_TAB) at runtime, identifying its
*&      key fields, field names, types, and descriptive texts.
*&   2. Data Retrieval:
*&      Selects matching change log records from DBTABLOG.
*&   3. Dynamic Decoding:
*&      Instantiates dynamic row variables of type (P_TAB). Decodes the raw
*&      LRAW data bytes of DBTABLOG-LOGDATA by casting them to the dynamic
*&      structure using intermediate variables to perform safe value copies.
*&   4. Key Reconstruction:
*&      Parses DBTABLOG-LOGKEY using RTTI offsets and lengths of the table's
*&      key columns, populating key fields in the dynamic row instances.
*&   5. Field-Level Comparison:
*&      Compares old and new row states. For updates (optype = 'U'), the
*&      new state is resolved either from the next log entry in sequence
*&      or by selecting the active row from the database (fallback).
*&      Identifies changed fields and records old/new value differences.
*&
*& SELECTION SCREEN PARAMETERS:
*&   - P_TAB: Name of the database table to explore (e.g. USR05, NACH)
*&   - S_LOGDAT: Filter change log date range
*&   - S_KEY: Filter change log concatenated key
*&   - S_USERA: Filter by the user who made the change
*&   - S_TCODE: Filter by the transaction code that triggered the change
*&   - S_OPTYPE: Filter by operation type (Insert, Update, Delete)
*&   - P_REAL: If checked, filters out entries where old & new values are identical
*&---------------------------------------------------------------------*
REPORT zsbtmp_gen_tree.

TABLES: dbtablog.
TYPE-POOLS: icon.

TYPES: ty_it_events TYPE STANDARD TABLE OF cntl_simple_event WITH DEFAULT KEY,
       ty_it_nodes  TYPE STANDARD TABLE OF mtreesnode WITH DEFAULT KEY.

*---------------------------------------------------------------------*
* SELECTION SCREEN
*---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
PARAMETERS: p_tab TYPE tabname DEFAULT 'USR05' OBLIGATORY.
SELECT-OPTIONS: s_logdat FOR dbtablog-logdate.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-b02.
SELECT-OPTIONS: s_key    FOR dbtablog-logkey,
                s_usera  FOR dbtablog-username,
                s_tcode  FOR dbtablog-tcode,
                s_optype FOR dbtablog-optype DEFAULT 'U'.
PARAMETERS: p_real AS CHECKBOX DEFAULT abap_true.
SELECTION-SCREEN END OF BLOCK b02.

INITIALIZATION.
  s_logdat[] = VALUE #( ( sign = 'I' option = 'EQ'
                           low = sy-datum - 10
                          high = sy-datum ) ).

*---------------------------------------------------------------------*
* LCL_REPORT DEFINITION
*---------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_output,
             tabname   TYPE dbtablog-tabname,
             logdate   TYPE dbtablog-logdate,
             logtime   TYPE dbtablog-logtime,
             username  TYPE dbtablog-username,
             tcode     TYPE dbtablog-tcode,
             optype    TYPE dbtablog-optype,
             tabkey    TYPE txw_cd_gen-tabkey,
             fname     TYPE txw_cd_gen-fname,
             ftext     TYPE txw_cd_gen-ftext,
             value_old TYPE txw_cd_gen-value_old,
             value_new TYPE txw_cd_gen-value_new,
             udate     TYPE txw_cd_gen-udate,
             utime     TYPE txw_cd_gen-utime,
             chngind   TYPE txw_cd_gen-chngind,
             langu     TYPE txw_cd_gen-langu,
             icon      TYPE icon_d,
             color     TYPE lvc_t_scol,
             key_disp  TYPE string,
           END OF ty_output,
           tt_dbtablog TYPE STANDARD TABLE OF dbtablog WITH DEFAULT KEY,
           BEGIN OF ty_node_map,
             node_key TYPE salv_de_node_key,
             key_disp TYPE string,
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
      mt_dfies    TYPE ddfields,
      it_nodes    TYPE ty_it_nodes,
      go_alv      TYPE REF TO cl_salv_table,
      go_tree     TYPE REF TO cl_gui_simple_tree.

    CLASS-METHODS:
      get_data,
      display_split_screen,
      display_batch,
      build_tree,
      setup_alv_grid,
      init_output_row
        IMPORTING
          is_dblog      TYPE dbtablog
        RETURNING
          VALUE(rs_out) TYPE ty_output,
      build_key_disp
        IMPORTING
          is_row             TYPE any
        RETURNING
          VALUE(rv_key_disp) TYPE string,
      get_next_row
        IMPORTING
          is_dbtablog   TYPE dbtablog
          id_tabix_next TYPE i
          it_dbtablog   TYPE tt_dbtablog
        CHANGING
          cr_row_new    TYPE REF TO data,
      populate_key_fields
        IMPORTING
          is_dblog TYPE dbtablog
        CHANGING
          cs_row   TYPE any.
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
    IF mt_all_logs IS INITIAL.
      IF sy-langu = 'D'.
        MESSAGE 'Keine Protokolleinträge zu den Selektionskriterien gefunden.' TYPE 'S' DISPLAY LIKE 'W'.
      ELSE.
        MESSAGE 'No change log entries found matching selection criteria.' TYPE 'S' DISPLAY LIKE 'W'.
      ENDIF.
      RETURN.
    ENDIF.

    IF sy-batch = abap_true.
      display_batch( ).
    ELSE.
      display_split_screen( ).
    ENDIF.
  ENDMETHOD.

  METHOD get_data.
    DATA: lt_dblog   TYPE tt_dbtablog,
          lr_row_new TYPE REF TO data,
          lr_row_old TYPE REF TO data.

    FIELD-SYMBOLS: <ls_row_new>   TYPE any,
                   <ls_row_old>   TYPE any,
                   <lv_val_new>   TYPE any,
                   <lv_val_old>   TYPE any,
                   <ls_data_cast> TYPE any.

    DATA(lo_struct) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( p_tab ) ).
    TRY.
        mt_dfies = lo_struct->get_ddic_field_list( ).
      CATCH cx_root.
        IF sy-langu = 'D'.
          MESSAGE 'Ungültiger Tabellenname oder Tabelle im Dictionary nicht aktiv.' TYPE 'E'.
        ELSE.
          MESSAGE 'Invalid table name or table not active in Dictionary.' TYPE 'E'.
        ENDIF.
    ENDTRY.

    SELECT * FROM dbtablog
      WHERE tabname  = @p_tab
        AND logdate  IN @s_logdat
        AND logkey   IN @s_key
        AND username IN @s_usera
        AND tcode    IN @s_tcode
        AND optype   IN @s_optype
      ORDER BY logkey ASCENDING, logdate ASCENDING, logtime ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @lt_dblog.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    TRY.
        CREATE DATA lr_row_new TYPE (p_tab).
        ASSIGN lr_row_new->* TO <ls_row_new>.
        CREATE DATA lr_row_old TYPE (p_tab).
        ASSIGN lr_row_old->* TO <ls_row_old>.
      CATCH cx_root.
        RETURN.
    ENDTRY.

    LOOP AT lt_dblog ASSIGNING FIELD-SYMBOL(<ls_dblog>).
      DATA(lv_tabix) = sy-tabix.
      CLEAR: <ls_row_new>, <ls_row_old>.

      CASE <ls_dblog>-optype.
        WHEN 'I'.
          ASSIGN <ls_dblog>-logdata TO <ls_data_cast> CASTING TYPE (p_tab).
          IF sy-subrc = 0.
            <ls_row_new> = <ls_data_cast>.
            populate_key_fields( EXPORTING is_dblog = <ls_dblog> CHANGING cs_row = <ls_row_new> ).
            LOOP AT mt_dfies INTO DATA(ls_field) WHERE keyflag = ' '.
              ASSIGN COMPONENT ls_field-fieldname OF STRUCTURE <ls_row_new> TO <lv_val_new>.
              IF sy-subrc = 0 AND <lv_val_new> IS NOT INITIAL.
                DATA(ls_out) = init_output_row( <ls_dblog> ).
                ls_out-fname     = ls_field-fieldname.
                ls_out-ftext     = ls_field-fieldtext.
                ls_out-value_old = ''.
                ls_out-value_new = |{ <lv_val_new> }|.
                ls_out-icon      = icon_create.
                APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO ls_out-color.
                ls_out-key_disp  = build_key_disp( <ls_row_new> ).
                APPEND ls_out TO mt_all_logs.
              ENDIF.
            ENDLOOP.
          ENDIF.

        WHEN 'D'.
          ASSIGN <ls_dblog>-logdata TO <ls_data_cast> CASTING TYPE (p_tab).
          IF sy-subrc = 0.
            <ls_row_old> = <ls_data_cast>.
            populate_key_fields( EXPORTING is_dblog = <ls_dblog> CHANGING cs_row = <ls_row_old> ).
            LOOP AT mt_dfies INTO ls_field WHERE keyflag = ' '.
              ASSIGN COMPONENT ls_field-fieldname OF STRUCTURE <ls_row_old> TO <lv_val_old>.
              IF sy-subrc = 0 AND <lv_val_old> IS NOT INITIAL.
                ls_out = init_output_row( <ls_dblog> ).
                ls_out-fname     = ls_field-fieldname.
                ls_out-ftext     = ls_field-fieldtext.
                ls_out-value_old = |{ <lv_val_old> }|.
                ls_out-value_new = ''.
                ls_out-icon      = icon_delete.
                APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 3 int = 1 ) ) TO ls_out-color.
                ls_out-key_disp  = build_key_disp( <ls_row_old> ).
                APPEND ls_out TO mt_all_logs.
              ENDIF.
            ENDLOOP.
          ENDIF.

        WHEN 'U'.
          ASSIGN <ls_dblog>-logdata TO <ls_data_cast> CASTING TYPE (p_tab).
          IF sy-subrc = 0.
            <ls_row_old> = <ls_data_cast>.
            populate_key_fields( EXPORTING is_dblog = <ls_dblog> CHANGING cs_row = <ls_row_old> ).
            get_next_row(
              EXPORTING
                is_dbtablog   = <ls_dblog>
                id_tabix_next = lv_tabix + 1
                it_dbtablog   = lt_dblog
              CHANGING
                cr_row_new    = lr_row_new ).

            LOOP AT mt_dfies INTO ls_field WHERE keyflag = ' '.
              ASSIGN COMPONENT ls_field-fieldname OF STRUCTURE <ls_row_old> TO <lv_val_old>.
              IF sy-subrc = 0.
                ASSIGN COMPONENT ls_field-fieldname OF STRUCTURE <ls_row_new> TO <lv_val_new>.
                IF sy-subrc = 0.
                  IF <lv_val_old> <> <lv_val_new>.
                    ls_out = init_output_row( <ls_dblog> ).
                    ls_out-fname     = ls_field-fieldname.
                    ls_out-ftext     = ls_field-fieldtext.
                    ls_out-value_old = |{ <lv_val_old> }|.
                    ls_out-value_new = |{ <lv_val_new> }|.
                    ls_out-icon      = icon_change.

                    IF p_real = abap_true AND ls_out-value_old = ls_out-value_new.
                      CONTINUE.
                    ENDIF.

                    APPEND VALUE #( fname = 'VALUE_OLD' color = VALUE #( col = 6 int = 1 ) ) TO ls_out-color.
                    APPEND VALUE #( fname = 'VALUE_NEW' color = VALUE #( col = 5 int = 1 ) ) TO ls_out-color.
                    ls_out-key_disp  = build_key_disp( <ls_row_old> ).
                    APPEND ls_out TO mt_all_logs.
                  ENDIF.
                ENDIF.
              ENDIF.
            ENDLOOP.
          ENDIF.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD init_output_row.
    rs_out = CORRESPONDING #( is_dblog ).
    rs_out-username  = is_dblog-username.
    rs_out-udate     = is_dblog-logdate.
    rs_out-utime     = is_dblog-logtime.
    rs_out-tcode     = is_dblog-tcode.
    rs_out-chngind   = is_dblog-optype.
    rs_out-langu     = is_dblog-language.

    DATA(ld_key_len) = strlen( is_dblog-logkey ).
    IF ld_key_len <= 70.
      rs_out-tabkey = is_dblog-logkey.
    ELSE.
      rs_out-tabkey = |{ is_dblog-logkey(69) }*|.
    ENDIF.
  ENDMETHOD.

  METHOD build_key_disp.
    DATA: lt_parts TYPE STANDARD TABLE OF string.
    LOOP AT mt_dfies INTO DATA(ls_df) WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
      ASSIGN COMPONENT ls_df-fieldname OF STRUCTURE is_row TO FIELD-SYMBOL(<lv_val>).
      IF sy-subrc = 0.
        DATA(lv_val_str) = |{ <lv_val> }|.
        CONDENSE lv_val_str.
        IF lv_val_str IS NOT INITIAL.
          APPEND lv_val_str TO lt_parts.
        ENDIF.
      ENDIF.
    ENDLOOP.
    CONCATENATE LINES OF lt_parts INTO rv_key_disp SEPARATED BY ' - '.
  ENDMETHOD.

  METHOD get_next_row.
    FIELD-SYMBOLS: <ls_row_new>   TYPE any,
                   <ls_data_cast> TYPE any.
    ASSIGN cr_row_new->* TO <ls_row_new>.
    CLEAR <ls_row_new>.

    READ TABLE it_dbtablog INTO DATA(ls_next) INDEX id_tabix_next.
    IF sy-subrc = 0 AND ls_next-logkey = is_dbtablog-logkey.
      ASSIGN ls_next-logdata TO <ls_data_cast> CASTING TYPE (is_dbtablog-tabname).
      IF sy-subrc = 0.
        <ls_row_new> = <ls_data_cast>.
        populate_key_fields( EXPORTING is_dblog = ls_next CHANGING cs_row = <ls_row_new> ).
        RETURN.
      ENDIF.
    ENDIF.

    DATA: lt_next_logs TYPE STANDARD TABLE OF dbtablog.
    SELECT dataln, logdata FROM dbtablog
      WHERE tabname = @is_dbtablog-tabname
        AND logkey  = @is_dbtablog-logkey
        AND ( logdate > @is_dbtablog-logdate OR ( logdate = @is_dbtablog-logdate AND logtime > @is_dbtablog-logtime ) )
      ORDER BY logdate ASCENDING, logtime ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @lt_next_logs
      UP TO 1 ROWS.
    IF sy-subrc = 0.
      READ TABLE lt_next_logs INTO DATA(ls_next_db) INDEX 1.
      IF sy-subrc = 0.
        ASSIGN ls_next_db-logdata TO <ls_data_cast> CASTING TYPE (is_dbtablog-tabname).
        IF sy-subrc = 0.
          <ls_row_new> = <ls_data_cast>.
          populate_key_fields( EXPORTING is_dblog = ls_next_db CHANGING cs_row = <ls_row_new> ).
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.

    DATA: lt_where   TYPE STANDARD TABLE OF string,
          lv_where   TYPE string,
          lr_row_old TYPE REF TO data.

    FIELD-SYMBOLS: <ls_row_old> TYPE any.

    TRY.
        CREATE DATA lr_row_old TYPE (is_dbtablog-tabname).
        ASSIGN lr_row_old->* TO <ls_row_old>.
        IF sy-subrc = 0.
          ASSIGN is_dbtablog-logdata TO <ls_data_cast> CASTING TYPE (is_dbtablog-tabname).
          IF sy-subrc = 0.
            <ls_row_old> = <ls_data_cast>.
            populate_key_fields( EXPORTING is_dblog = is_dbtablog CHANGING cs_row = <ls_row_old> ).
          ELSE.
            RETURN.
          ENDIF.
        ELSE.
          RETURN.
        ENDIF.
      CATCH cx_root.
        RETURN.
    ENDTRY.

    LOOP AT mt_dfies INTO DATA(ls_df) WHERE keyflag = 'X' AND fieldname <> 'MANDT'.
      ASSIGN COMPONENT ls_df-fieldname OF STRUCTURE <ls_row_old> TO FIELD-SYMBOL(<lv_val>).
      IF sy-subrc = 0.
        DATA(lv_val_str) = |{ <lv_val> }|.
        REPLACE ALL OCCURRENCES OF `'` IN lv_val_str WITH `''`.
        APPEND |{ ls_df-fieldname } = '{ lv_val_str }'| TO lt_where.
      ENDIF.
    ENDLOOP.

    IF line_exists( mt_dfies[ fieldname = 'MANDT' ] ).
      APPEND |MANDT = '{ sy-mandt }'| TO lt_where.
    ENDIF.

    CONCATENATE LINES OF lt_where INTO lv_where SEPARATED BY ' AND '.

    DATA: lt_select_fields TYPE STANDARD TABLE OF string.
    LOOP AT mt_dfies INTO DATA(ls_df_sel).
      APPEND ls_df_sel-fieldname TO lt_select_fields.
    ENDLOOP.

    SELECT SINGLE (lt_select_fields) FROM (is_dbtablog-tabname)
      WHERE (lv_where)
      INTO @<ls_row_new>.
    IF sy-subrc <> 0.
      CLEAR <ls_row_new>.
    ENDIF.
  ENDMETHOD.

  METHOD display_split_screen.
    DATA: lo_split     TYPE REF TO cl_gui_splitter_container,
          lo_spl_left  TYPE REF TO cl_gui_container,
          lo_spl_right TYPE REF TO cl_gui_container,
          it_events    TYPE ty_it_events.

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
        CREATE OBJECT go_tree
          EXPORTING
            parent              = lo_spl_left
            node_selection_mode = cl_gui_simple_tree=>node_sel_mode_single.

        APPEND VALUE #( eventid    = cl_gui_simple_tree=>eventid_selection_changed
                        appl_event = abap_true ) TO it_events.
        go_tree->set_registered_events( events = it_events ).

        SET HANDLER lcl_event_handler=>on_selection_changed FOR go_tree.

        mt_grid_log = mt_all_logs.

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

  METHOD display_batch.
    TRY.
        cl_salv_table=>factory(
          EXPORTING
            list_display = abap_true
          IMPORTING
            r_salv_table = go_alv
          CHANGING
            t_table      = mt_all_logs ).

        setup_alv_grid( ).
        go_alv->display( ).
      CATCH cx_root INTO DATA(lo_err).
        MESSAGE lo_err->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD build_tree.
    DATA: lv_prev_key TYPE string,
          lv_node_key TYPE salv_de_node_key,
          lv_node_idx TYPE i VALUE 0.

    DATA(lv_total_count) = lines( mt_all_logs ).

    APPEND VALUE #( node_key  = 'ROOT'
                    relatship = cl_gui_simple_tree=>relat_last_child
                    isfolder  = abap_true
                    n_image   = icon_folder
                    exp_image = icon_open_folder
                    style     = cl_gui_simple_tree=>style_default
                    text      = |Table log entries ({ lv_total_count })| ) TO it_nodes.

    LOOP AT mt_all_logs ASSIGNING FIELD-SYMBOL(<ls_log>).
      IF <ls_log>-key_disp <> lv_prev_key.
        lv_prev_key = <ls_log>-key_disp.

        lv_node_idx = lv_node_idx + 1.
        lv_node_key = |N{ lv_node_idx }|.

        DATA(lv_key_count) = 0.
        LOOP AT mt_all_logs TRANSPORTING NO FIELDS WHERE key_disp = lv_prev_key.
          lv_key_count = lv_key_count + 1.
        ENDLOOP.

        APPEND VALUE #( node_key  = lv_node_key
                        relatship = cl_gui_simple_tree=>relat_last_child
                        relatkey  = 'ROOT'
                        isfolder  = abap_false
                        style     = cl_gui_simple_tree=>style_default
                        text      = |Key: { lv_prev_key } ({ lv_key_count })| ) TO it_nodes.

        APPEND VALUE #( node_key = lv_node_key
                        key_disp = lv_prev_key ) TO mt_node_map.
      ENDIF.
    ENDLOOP.

    go_tree->add_nodes(
      EXPORTING
        table_structure_name = 'MTREESNODE'
        node_table           = it_nodes ).

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

    DATA: lt_hide TYPE STANDARD TABLE OF salv_de_column WITH DEFAULT KEY.
    lt_hide = VALUE #( ( 'MANDT' )
                       ( 'TABNAME' )
                       ( 'TABKEY' )
                       ( 'OPTYPE' )
                       ( 'UDATE' )
                       ( 'UTIME' )
                       ( 'VERSNO' )
                       ( 'COLOR' )
                       ( 'KEY_DISP' ) ).
    LOOP AT lt_hide INTO DATA(lv_col).
      TRY.
          lo_cols->get_column( lv_col )->set_visible( abap_false ).
        CATCH cx_salv_not_found.
      ENDTRY.
    ENDLOOP.

    TRY.
        DATA: lo_col_table TYPE REF TO cl_salv_column_table.
        lo_col_table ?= lo_cols->get_column( 'ICON' ).
        lo_col_table->set_icon( abap_true ).
        lo_col_table->set_medium_text( 'Change Type' ).
      CATCH cx_salv_error.
    ENDTRY.

    go_alv->get_functions( )->set_all( abap_true ).
  ENDMETHOD.

  METHOD refresh_grid.
    DATA: ls_log TYPE ty_output.

    READ TABLE mt_node_map INTO DATA(ls_map) WITH KEY node_key = id_node_key.
    IF sy-subrc = 0.
      CLEAR mt_grid_log.
      LOOP AT mt_all_logs INTO ls_log WHERE key_disp = ls_map-key_disp.
        APPEND ls_log TO mt_grid_log.
      ENDLOOP.
      go_alv->refresh( ).
    ENDIF.
  ENDMETHOD.

  METHOD populate_key_fields.
    DATA: lv_offset TYPE i VALUE 0.
    LOOP AT mt_dfies INTO DATA(ls_df) WHERE keyflag = 'X'.
      ASSIGN COMPONENT ls_df-fieldname OF STRUCTURE cs_row TO FIELD-SYMBOL(<lv_key_val>).
      IF sy-subrc = 0.
        DATA(lv_len) = ls_df-leng.
        DATA(lv_logkey_len) = strlen( is_dblog-logkey ).
        IF lv_offset + lv_len <= lv_logkey_len.
          <lv_key_val> = is_dblog-logkey+lv_offset(lv_len).
        ELSE.
          DATA(lv_rem) = lv_logkey_len - lv_offset.
          IF lv_rem > 0.
            <lv_key_val> = is_dblog-logkey+lv_offset(lv_rem).
          ENDIF.
        ENDIF.
      ENDIF.
      lv_offset = lv_offset + ls_df-leng.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
