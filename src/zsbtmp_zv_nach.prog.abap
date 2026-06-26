*&---------------------------------------------------------------------*
*& Report ZSBTMP_ZV_NACH
*&---------------------------------------------------------------------*
*& Maintenance program for message condition records (NACH) in S/4HANA
*& Rebuilds the VAKEY field dynamically from the condition tables Bxxx
*&---------------------------------------------------------------------*
REPORT zsbtmp_zv_nach.

TABLES: nach.

TYPE-POOLS: icon.

*---------------------------------------------------------------------*
* DATA DEFINITIONS
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_output.
         INCLUDE STRUCTURE nach.
TYPES:   vakey_disp TYPE char100,
       END OF ty_output.

DATA: gt_output    TYPE STANDARD TABLE OF ty_output,
      gt_original  TYPE STANDARD TABLE OF ty_output,
      go_grid      TYPE REF TO cl_gui_alv_grid,
      gv_edit_mode TYPE abap_bool.

*---------------------------------------------------------------------*
* SELECTION SCREEN
*---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-t01.
SELECT-OPTIONS: s_kappl FOR nach-kappl,
                s_kschl FOR nach-kschl,
                s_kotab FOR nach-kotabnr,
                s_ernam FOR nach-ernam,
                s_erdat FOR nach-erdat,
                s_knumh FOR nach-knumh.
SELECTION-SCREEN END OF BLOCK b1.

*---------------------------------------------------------------------*
* CLASS lcl_vakey_builder DEFINITION
*---------------------------------------------------------------------*
CLASS lcl_vakey_builder DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_field_info,
             fieldname TYPE fieldname,
           END OF ty_field_info,
           tt_field_info TYPE STANDARD TABLE OF ty_field_info WITH DEFAULT KEY.

    CLASS-METHODS:
      get_vakey
        IMPORTING
          iv_kotabnr      TYPE kotabnr
          iv_knumh        TYPE knumh
        RETURNING
          VALUE(rv_vakey) TYPE vakey.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_table_fields,
             tabname TYPE tabname,
             fields  TYPE tt_field_info,
           END OF ty_table_fields.

    CLASS-DATA:
      st_table_cache TYPE HASHED TABLE OF ty_table_fields WITH UNIQUE KEY tabname.

    CLASS-METHODS:
      get_table_key_fields
        IMPORTING
          iv_tabname       TYPE tabname
        RETURNING
          VALUE(rt_fields) TYPE tt_field_info.
ENDCLASS.

*---------------------------------------------------------------------*
* CLASS lcl_vakey_builder IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_vakey_builder IMPLEMENTATION.
  METHOD get_table_key_fields.
    READ TABLE st_table_cache WITH TABLE KEY tabname = iv_tabname INTO DATA(ls_cache).
    IF sy-subrc = 0.
      rt_fields = ls_cache-fields.
      RETURN.
    ENDIF.

    DATA: lt_dfies TYPE ddfields.
    TRY.
        DATA(lo_struct) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( iv_tabname ) ).
        lt_dfies = lo_struct->get_ddic_field_list( ).

        LOOP AT lt_dfies INTO DATA(ls_dfies) WHERE keyflag = 'X'
                                              AND fieldname <> 'MANDT'
                                              AND fieldname <> 'KAPPL'
                                              AND fieldname <> 'KSCHL'
                                              AND fieldname <> 'KNUMH'.
          APPEND VALUE #( fieldname = ls_dfies-fieldname ) TO rt_fields.
        ENDLOOP.

        INSERT VALUE #( tabname = iv_tabname fields = rt_fields ) INTO TABLE st_table_cache.
      CATCH cx_root.
        " If table doesn't exist or RTTI fails, cache empty list to avoid repeating failed attempts
        INSERT VALUE #( tabname = iv_tabname fields = rt_fields ) INTO TABLE st_table_cache.
    ENDTRY.
  ENDMETHOD.

  METHOD get_vakey.
    CLEAR rv_vakey.
    IF iv_kotabnr IS INITIAL OR iv_knumh IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_tabname) = |B{ iv_kotabnr }|.
    DATA(lt_fields) = get_table_key_fields( CONV tabname( lv_tabname ) ).
    IF lt_fields IS INITIAL.
      RETURN.
    ENDIF.

    DATA: lr_data TYPE REF TO data.
    FIELD-SYMBOLS: <ls_row> TYPE any.

    TRY.
        CREATE DATA lr_data TYPE (lv_tabname).
        ASSIGN lr_data->* TO <ls_row>.
      CATCH cx_root.
        RETURN.
    ENDTRY.

    DATA: lv_select_list TYPE string.
    LOOP AT lt_fields INTO DATA(ls_f).
      IF lv_select_list IS INITIAL.
        lv_select_list = ls_f-fieldname.
      ELSE.
        lv_select_list = |{ lv_select_list }, { ls_f-fieldname }|.
      ENDIF.
    ENDLOOP.
    IF lv_select_list IS INITIAL.
      lv_select_list = 'KNUMH'.
    ENDIF.

    SELECT SINGLE (lv_select_list) FROM (lv_tabname) WHERE knumh = @iv_knumh INTO CORRESPONDING FIELDS OF @<ls_row>.
    IF sy-subrc = 0.
      LOOP AT lt_fields INTO DATA(ls_field).
        ASSIGN COMPONENT ls_field-fieldname OF STRUCTURE <ls_row> TO FIELD-SYMBOL(<lv_val>).
        IF sy-subrc = 0.
          DATA(lv_str) = |{ <lv_val> }|.
          CONDENSE lv_str.
          IF rv_vakey IS INITIAL.
            rv_vakey = lv_str.
          ELSE.
            rv_vakey = |{ rv_vakey } { lv_str }|.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*---------------------------------------------------------------------*
* CLASS lcl_event_handler DEFINITION
*---------------------------------------------------------------------*
CLASS lcl_event_handler DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      handle_toolbar FOR EVENT toolbar OF cl_gui_alv_grid
        IMPORTING e_object e_interactive,
      handle_user_command FOR EVENT user_command OF cl_gui_alv_grid
        IMPORTING e_ucomm.
ENDCLASS.

*---------------------------------------------------------------------*
* CLASS lcl_report DEFINITION
*---------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      run,
      get_data,
      save_data,
      display_alv.
ENDCLASS.

*---------------------------------------------------------------------*
* CLASS lcl_event_handler IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_event_handler IMPLEMENTATION.
  METHOD handle_toolbar.
    DATA: lv_txt_disp   TYPE string,
          lv_qinfo_disp TYPE string,
          lv_txt_save   TYPE string,
          lv_qinfo_save TYPE string,
          lv_txt_edit   TYPE string,
          lv_qinfo_edit TYPE string.

    IF sy-langu = 'D'.
      lv_txt_disp   = 'Anzeigen'.
      lv_qinfo_disp = 'In den Anzeigemodus wechseln'.
      lv_txt_save   = 'Sichern'.
      lv_qinfo_save = 'Änderungen sichern'.
      lv_txt_edit   = 'Ändern'.
      lv_qinfo_edit = 'In den Änderungsmodus wechseln'.
    ELSE.
      lv_txt_disp   = 'Display'.
      lv_qinfo_disp = 'Switch to Display Mode'.
      lv_txt_save   = 'Save'.
      lv_qinfo_save = 'Save Changes'.
      lv_txt_edit   = 'Edit'.
      lv_qinfo_edit = 'Switch to Edit Mode'.
    ENDIF.

    IF gv_edit_mode = abap_true.
      APPEND VALUE #( butn_type = 3 ) TO e_object->mt_toolbar.
      APPEND VALUE #(
        function  = 'DISPLAY'
        icon      = icon_display
        quickinfo = CONV iconquick( lv_qinfo_disp )
        text      = CONV buttontext( lv_txt_disp )
        disabled  = abap_false
      ) TO e_object->mt_toolbar.
      APPEND VALUE #(
        function  = 'SAVE'
        icon      = icon_system_save
        quickinfo = CONV iconquick( lv_qinfo_save )
        text      = CONV buttontext( lv_txt_save )
        disabled  = abap_false
      ) TO e_object->mt_toolbar.
    ELSE.
      APPEND VALUE #( butn_type = 3 ) TO e_object->mt_toolbar.
      APPEND VALUE #(
        function  = 'EDIT'
        icon      = icon_change
        quickinfo = CONV iconquick( lv_qinfo_edit )
        text      = CONV buttontext( lv_txt_edit )
        disabled  = abap_false
      ) TO e_object->mt_toolbar.
    ENDIF.
  ENDMETHOD.

  METHOD handle_user_command.
    CASE e_ucomm.
      WHEN 'SAVE'.
        lcl_report=>save_data( ).
      WHEN 'EDIT'.
        gv_edit_mode = abap_true.
        IF go_grid IS BOUND.
          go_grid->set_ready_for_input( 1 ).
          go_grid->refresh_table_display( ).
        ENDIF.
      WHEN 'DISPLAY'.
        gv_edit_mode = abap_false.
        IF go_grid IS BOUND.
          go_grid->set_ready_for_input( 0 ).
          go_grid->refresh_table_display( ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

*---------------------------------------------------------------------*
* CLASS lcl_report IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_report IMPLEMENTATION.
  METHOD run.
    gv_edit_mode = abap_false.
    get_data( ).
    IF gt_output IS INITIAL.
      IF sy-langu = 'D'.
        MESSAGE 'Keine Nachrichtenkonditionen zu den Selektionskriterien gefunden.' TYPE 'S' DISPLAY LIKE 'W'.
      ELSE.
        MESSAGE 'No condition records found matching selection criteria.' TYPE 'S' DISPLAY LIKE 'W'.
      ENDIF.
      RETURN.
    ENDIF.

    IF go_grid IS BOUND.
      go_grid->free( ).
      CLEAR go_grid.
    ENDIF.

    display_alv( ).

    cl_abap_list_layout=>suppress_toolbar( ).
    WRITE space.
  ENDMETHOD.

  METHOD get_data.
    CLEAR: gt_output, gt_original.

    SELECT * FROM nach
      INTO CORRESPONDING FIELDS OF TABLE @gt_output
      WHERE kappl IN @s_kappl
        AND kschl IN @s_kschl
        AND kotabnr IN @s_kotab
        AND ernam IN @s_ernam
        AND erdat IN @s_erdat
        AND knumh IN @s_knumh.
    IF sy-subrc <> 0.
      " gt_output remains empty, handled during display validation
    ENDIF.

    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      <ls_out>-vakey_disp = lcl_vakey_builder=>get_vakey(
        iv_kotabnr = <ls_out>-kotabnr
        iv_knumh   = <ls_out>-knumh ).
    ENDLOOP.

    gt_original = gt_output.
  ENDMETHOD.

  METHOD save_data.
    IF go_grid IS BOUND.
      go_grid->check_changed_data( ).
    ENDIF.

    DATA: lt_locked_keys TYPE STANDARD TABLE OF rstable-varkey,
          lv_success     TYPE i,
          lv_failed      TYPE i,
          lv_failed_lock TYPE abap_bool.

    LOOP AT gt_output INTO DATA(ls_out).
      READ TABLE gt_original INTO DATA(ls_orig) WITH KEY knumh = ls_out-knumh.
      IF sy-subrc = 0.
        DATA(ls_nach_new) = CORRESPONDING nach( ls_out ).
        DATA(ls_nach_old) = CORRESPONDING nach( ls_orig ).
        IF ls_nach_new <> ls_nach_old.
          DATA(lv_varkey) = CONV rstable-varkey( |{ sy-mandt }{ ls_out-knumh }| ).
          CALL FUNCTION 'ENQUEUE_E_TABLE'
            EXPORTING
              mode_rstable   = 'E'
              tabname        = 'NACH'
              varkey         = lv_varkey
            EXCEPTIONS
              foreign_lock   = 1
              system_failure = 2
              OTHERS         = 3.
          IF sy-subrc = 0.
            APPEND lv_varkey TO lt_locked_keys.
            UPDATE nach FROM @ls_nach_new.
            IF sy-subrc = 0.
              lv_success = lv_success + 1.
            ELSE.
              lv_failed = lv_failed + 1.
            ENDIF.
          ELSE.
            lv_failed_lock = abap_true.
            EXIT.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF lv_failed_lock = abap_true.
      ROLLBACK WORK.
      LOOP AT lt_locked_keys INTO DATA(lv_key).
        CALL FUNCTION 'DEQUEUE_E_TABLE'
          EXPORTING
            mode_rstable = 'E'
            tabname      = 'NACH'
            varkey       = lv_key.
      ENDLOOP.
      IF sy-langu = 'D'.
        MESSAGE 'Sichern abgebrochen: Ein Datensatz ist von einem anderen Benutzer gesperrt.' TYPE 'E'.
      ELSE.
        MESSAGE 'Save aborted: One of the records is locked by another user.' TYPE 'E'.
      ENDIF.
      RETURN.
    ENDIF.

    IF lv_success > 0.
      COMMIT WORK.
      LOOP AT lt_locked_keys INTO lv_key.
        CALL FUNCTION 'DEQUEUE_E_TABLE'
          EXPORTING
            mode_rstable = 'E'
            tabname      = 'NACH'
            varkey       = lv_key.
      ENDLOOP.
      gt_original = gt_output.
      IF sy-langu = 'D'.
        MESSAGE |Es wurden { lv_success } Sätze erfolgreich gesichert.| TYPE 'S'.
      ELSE.
        MESSAGE |Saved { lv_success } records successfully.| TYPE 'S'.
      ENDIF.
      IF go_grid IS BOUND.
        go_grid->refresh_table_display( ).
      ENDIF.
    ELSEIF lv_failed > 0.
      ROLLBACK WORK.
      LOOP AT lt_locked_keys INTO lv_key.
        CALL FUNCTION 'DEQUEUE_E_TABLE'
          EXPORTING
            mode_rstable = 'E'
            tabname      = 'NACH'
            varkey       = lv_key.
      ENDLOOP.
      IF sy-langu = 'D'.
        MESSAGE 'Sichern fehlgeschlagen: Datenbankfehler aufgetreten.' TYPE 'E'.
      ELSE.
        MESSAGE 'Save failed: Database error occurred.' TYPE 'E'.
      ENDIF.
    ELSE.
      IF sy-langu = 'D'.
        MESSAGE 'Es wurden keine Änderungen festgestellt.' TYPE 'S'.
      ELSE.
        MESSAGE 'No changes were detected.' TYPE 'S'.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD display_alv.
    CREATE OBJECT go_grid
      EXPORTING
        i_parent = cl_gui_container=>default_screen.

    DATA: lt_dropdown TYPE lvc_t_dral.

    IF sy-langu = 'D'.
      " Dropdown handle 1: VSZTP (Sendezeitpunkt)
      APPEND VALUE #( handle = 1 value = '1' int_value = '1 - Senden durch periodisch eingeplanten Job' ) TO lt_dropdown.
      APPEND VALUE #( handle = 1 value = '2' int_value = '2 - Senden durch Job mit Zusatzangaben' ) TO lt_dropdown.
      APPEND VALUE #( handle = 1 value = '3' int_value = '3 - Senden durch anwendungseigene Transaktion' ) TO lt_dropdown.
      APPEND VALUE #( handle = 1 value = '4' int_value = '4 - Sofort senden (beim Sichern der Anwendung)' ) TO lt_dropdown.

      " Dropdown handle 2: TDARMOD (Archivierungsmodus)
      APPEND VALUE #( handle = 2 value = '1' int_value = '1 - Nur Drucken' ) TO lt_dropdown.
      APPEND VALUE #( handle = 2 value = '2' int_value = '2 - Nur Archivieren' ) TO lt_dropdown.
      APPEND VALUE #( handle = 2 value = '3' int_value = '3 - Drucken und Archivieren' ) TO lt_dropdown.

      " Dropdown handle 3: NACHA (Sendemedium)
      APPEND VALUE #( handle = 3 value = '1' int_value = '1 - Druckausgabe' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '2' int_value = '2 - Telefax' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '4' int_value = '4 - Telex' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '5' int_value = '5 - Externes Senden' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '7' int_value = '7 - E-Mail' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '8' int_value = '8 - Sonderfunktion' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '9' int_value = '9 - Ereignis (Workflow)' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = 'A' int_value = 'A - Verteilung (ALE)' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = 'I' int_value = 'I - Externes Senden (Kommunikationsstrategie)' ) TO lt_dropdown.

      " Dropdown handle 4: TDOCOVER (Deckblatt drucken)
      APPEND VALUE #( handle = 4 value = ' ' int_value = 'Standard' ) TO lt_dropdown.
      APPEND VALUE #( handle = 4 value = 'X' int_value = 'X - Ja (Deckblatt drucken)' ) TO lt_dropdown.
      APPEND VALUE #( handle = 4 value = 'N' int_value = 'N - Nein (Kein Deckblatt)' ) TO lt_dropdown.
    ELSE.
      " Dropdown handle 1: VSZTP (Sendezeitpunkt)
      APPEND VALUE #( handle = 1 value = '1' int_value = '1 - Send with periodically scheduled job' ) TO lt_dropdown.
      APPEND VALUE #( handle = 1 value = '2' int_value = '2 - Send with job, additional specification' ) TO lt_dropdown.
      APPEND VALUE #( handle = 1 value = '3' int_value = '3 - Send with application own transaction' ) TO lt_dropdown.
      APPEND VALUE #( handle = 1 value = '4' int_value = '4 - Send immediately (when saving application)' ) TO lt_dropdown.

      " Dropdown handle 2: TDARMOD (Archivierungsmodus)
      APPEND VALUE #( handle = 2 value = '1' int_value = '1 - Print only' ) TO lt_dropdown.
      APPEND VALUE #( handle = 2 value = '2' int_value = '2 - Archive only' ) TO lt_dropdown.
      APPEND VALUE #( handle = 2 value = '3' int_value = '3 - Print and archive' ) TO lt_dropdown.

      " Dropdown handle 3: NACHA (Sendemedium)
      APPEND VALUE #( handle = 3 value = '1' int_value = '1 - Print output' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '2' int_value = '2 - Fax' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '4' int_value = '4 - Telex' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '5' int_value = '5 - External send' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '7' int_value = '7 - E-Mail' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '8' int_value = '8 - Special function' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = '9' int_value = '9 - Events (Workflow)' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = 'A' int_value = 'A - Distribution (ALE)' ) TO lt_dropdown.
      APPEND VALUE #( handle = 3 value = 'I' int_value = 'I - External send (Comm. Strategy)' ) TO lt_dropdown.

      " Dropdown handle 4: TDOCOVER (Deckblatt drucken)
      APPEND VALUE #( handle = 4 value = ' ' int_value = 'Default (Standard)' ) TO lt_dropdown.
      APPEND VALUE #( handle = 4 value = 'X' int_value = 'X - Yes (Print cover page)' ) TO lt_dropdown.
      APPEND VALUE #( handle = 4 value = 'N' int_value = 'N - No (No cover page)' ) TO lt_dropdown.
    ENDIF.

    go_grid->set_drop_down_table( it_drop_down_alias = lt_dropdown ).

    DATA: lt_fieldcat TYPE lvc_t_fcat.
    CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
      EXPORTING
        i_structure_name       = 'NACH'
        i_bypassing_buffer     = 'X'
      CHANGING
        ct_fieldcat            = lt_fieldcat
      EXCEPTIONS
        inconsistent_interface = 1
        program_error          = 2
        OTHERS                 = 3.

    DATA: ls_fcat TYPE lvc_s_fcat.
    ls_fcat-fieldname = 'VAKEY_DISP'.
    IF sy-langu = 'D'.
      ls_fcat-scrtext_s = 'Var. Schl.'.
      ls_fcat-scrtext_m = 'Variabler Schlüssel'.
      ls_fcat-scrtext_l = 'Variabler Schlüssel'.
    ELSE.
      ls_fcat-scrtext_s = 'Var. Key'.
      ls_fcat-scrtext_m = 'Variable Key'.
      ls_fcat-scrtext_l = 'Variable Key'.
    ENDIF.
    ls_fcat-outputlen = 50.
    ls_fcat-col_pos   = 3.
    APPEND ls_fcat TO lt_fieldcat.

    LOOP AT lt_fieldcat ASSIGNING FIELD-SYMBOL(<ls_fcat>).
      IF <ls_fcat>-rollname CP 'NA_OBS*'.
        <ls_fcat>-no_out = 'X'.
      ENDIF.

      CASE <ls_fcat>-fieldname.
        WHEN 'VAKEY'.
          <ls_fcat>-edit   = abap_false.
        WHEN 'ANZAL' OR 'PFLD4' OR 'LDEST' OR 'DSNAM' OR 'DSUF1' OR 'DSUF2'.
          <ls_fcat>-edit = 'X'.
        WHEN 'DIMME' OR 'DELET'.
          <ls_fcat>-edit     = 'X'.
          <ls_fcat>-checkbox = 'X'.
        WHEN 'VSZTP'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '1'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 45.
        WHEN 'TDARMOD'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '2'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 30.
        WHEN 'NACHA'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '3'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 45.
        WHEN 'TDOCOVER'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '4'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 30.
        WHEN OTHERS.
          <ls_fcat>-edit = abap_false.
      ENDCASE.
    ENDLOOP.

    SORT lt_fieldcat BY col_pos.
    go_grid->set_ready_for_input( 0 ).

    DATA: ls_layout TYPE lvc_s_layo.
    IF sy-langu = 'D'.
      ls_layout-grid_title = 'Nachrichten-Konditionssätze (NACH)'.
    ELSE.
      ls_layout-grid_title = 'Message Condition Records (NACH)'.
    ENDIF.
    ls_layout-cwidth_opt = 'X'.
    ls_layout-zebra      = 'X'.

    SET HANDLER lcl_event_handler=>handle_toolbar FOR go_grid.
    SET HANDLER lcl_event_handler=>handle_user_command FOR go_grid.

    go_grid->register_edit_event( i_event_id = cl_gui_alv_grid=>mc_evt_enter ).
    go_grid->register_edit_event( i_event_id = cl_gui_alv_grid=>mc_evt_modified ).

    go_grid->set_table_for_first_display(
      EXPORTING
        is_layout                     = ls_layout
      CHANGING
        it_outtab                     = gt_output
        it_fieldcatalog               = lt_fieldcat
      EXCEPTIONS
        invalid_parameter_combination = 1
        program_error                 = 2
        too_many_lines                = 3
        OTHERS                        = 4 ).
  ENDMETHOD.
ENDCLASS.

*---------------------------------------------------------------------*
* START-OF-SELECTION
*---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_report=>run( ).
