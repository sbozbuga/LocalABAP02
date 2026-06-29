*&---------------------------------------------------------------------*
*& Report ZNACH
*&---------------------------------------------------------------------*
* Transaktion   ZNACH
* Datum         26.06.2026
*----------------------------------------------------------------------*
* Firma               CTDI GmbH Malsch Headquarter                     *
*                                                                      *
* Beschreibung:  (Funktion)                                            *
*& Maintenance program for message condition records (NACH) in S/4HANA
*& Rebuilds the VAKEY field dynamically from the condition tables Bxxx
*&---------------------------------------------------------------------*
* Anforderer:  M.Zaharia
* Ticket....:  2605-914
* Konzept...:  ???                                                     *
* Betreuung.:  ???                                                     *
*----------------------------------------------------------------------*
* Entwickler...: SBO-NHS003381
*
*----------------------------------------------------------------------*

************************************************************************
******************** !!!ACHTUNG BITTE BEACHTEN!!! **********************
************************************************************************
* !!!      Keine Korrekturen oder Erweiterungen ohne Absprache     !!! *
* !!!      mit der Anwendungsentwicklung                           !!! *
*----------------------------------------------------------------------*
* !!! Keine Korrekturen/Erweiterung ohne Dokumentation in Historie !!! *
************************************************************************
* Änderungshistorie                                                    *
*                                                                      *
* Datum      Entwickler  Bemerkung                                     *
*======================================================================*
* 29.06.2026 SBO-NHS003381 Farbhervorhebung geänderter Zeilen/Zellen   *
*                          & grüne Rückmeldung nach Speichern          *
*----------------------------------------------------------------------*
REPORT ZNACH NO STANDARD PAGE HEADING.

TABLES: nach.

TYPE-POOLS: icon.

*---------------------------------------------------------------------*
* DATA DEFINITIONS
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_output.
         INCLUDE STRUCTURE nach.
TYPES:   vakey_disp    TYPE char100,
         vsztp_disp    TYPE char50,
         tdarmod_disp  TYPE char50,
         nacha_disp    TYPE char50,
         tdocover_disp TYPE char50,
         cell_colors   TYPE lvc_t_scol,
         row_color     TYPE char4,
       END OF ty_output.

DATA: gt_output    TYPE STANDARD TABLE OF ty_output,
      gt_original  TYPE STANDARD TABLE OF ty_output,
      go_grid      TYPE REF TO cl_gui_alv_grid,
      gv_edit_mode TYPE abap_bool.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-t01.
SELECT-OPTIONS: s_kappl FOR nach-kappl,
                s_kschl FOR nach-kschl,
                s_kotab FOR nach-kotabnr,
                s_ernam FOR nach-ernam,
                s_erdat FOR nach-erdat,
                s_knumh FOR nach-knumh.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-t02.
PARAMETERS: p_vari TYPE disvariant-variant.
SELECTION-SCREEN END OF BLOCK b2.

*---------------------------------------------------------------------*
* SELECTION SCREEN EVENTS
*---------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_vari.
  DATA: ls_variant_f4 TYPE disvariant,
        lv_exit_f4    TYPE c.

  CLEAR ls_variant_f4.
  ls_variant_f4-report = sy-repid.

  CALL FUNCTION 'REUSE_ALV_VARIANT_F4'
    EXPORTING
      is_variant    = ls_variant_f4
      i_save        = 'A'
    IMPORTING
      e_exit        = lv_exit_f4
      es_variant    = ls_variant_f4
    EXCEPTIONS
      not_found     = 1
      program_error = 2
      OTHERS        = 3.
  IF sy-subrc = 0 AND lv_exit_f4 = space.
    p_vari = ls_variant_f4-variant.
  ENDIF.

AT SELECTION-SCREEN ON p_vari.
  IF p_vari IS NOT INITIAL.
    DATA: ls_variant_chk TYPE disvariant.
    ls_variant_chk-report  = sy-repid.
    ls_variant_chk-variant = p_vari.

    CALL FUNCTION 'REUSE_ALV_VARIANT_EXIST'
      EXPORTING
        is_variant    = ls_variant_chk
        i_save        = 'A'
      EXCEPTIONS
        wrong_input   = 1
        not_found     = 2
        program_error = 3
        OTHERS        = 4.
    IF sy-subrc <> 0.
      MESSAGE TEXT-m01 TYPE 'E'.
    ENDIF.
  ENDIF.

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
        IMPORTING e_ucomm,
      handle_data_changed_finished FOR EVENT data_changed_finished OF cl_gui_alv_grid
        IMPORTING e_modified et_good_cells.
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
      update_colors,
      check_before_exit
        RETURNING
          VALUE(rv_can_exit) TYPE abap_bool,
      display_alv.
ENDCLASS.

*---------------------------------------------------------------------*
* CLASS lcl_event_handler IMPLEMENTATION
*---------------------------------------------------------------------*
CLASS lcl_event_handler IMPLEMENTATION.
  METHOD handle_toolbar.
    IF gv_edit_mode = abap_true.
      APPEND VALUE #( butn_type = 3 ) TO e_object->mt_toolbar.
      APPEND VALUE #(
        function  = 'DISPLAY'
        icon      = icon_display
        quickinfo = CONV iconquick( TEXT-q01 )
        text      = CONV buttontext( TEXT-b01 )
        disabled  = abap_false
      ) TO e_object->mt_toolbar.
      APPEND VALUE #(
        function  = 'SAVE'
        icon      = icon_system_save
        quickinfo = CONV iconquick( TEXT-q02 )
        text      = CONV buttontext( TEXT-b02 )
        disabled  = abap_false
      ) TO e_object->mt_toolbar.
    ELSE.
      APPEND VALUE #( butn_type = 3 ) TO e_object->mt_toolbar.
      APPEND VALUE #(
        function  = 'EDIT'
        icon      = icon_change
        quickinfo = CONV iconquick( TEXT-q03 )
        text      = CONV buttontext( TEXT-b03 )
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

  METHOD handle_data_changed.
    lcl_report=>update_colors( ).
    IF go_grid IS BOUND.
      go_grid->refresh_table_display( ).
    ENDIF.
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
      MESSAGE TEXT-m02 TYPE 'S' DISPLAY LIKE 'W'.
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
      <ls_out>-vsztp_disp    = <ls_out>-vsztp.
      <ls_out>-tdarmod_disp  = <ls_out>-tdarmod.
      <ls_out>-nacha_disp    = <ls_out>-nacha.
      <ls_out>-tdocover_disp = <ls_out>-tdocover.
    ENDLOOP.

    gt_original = gt_output.
  ENDMETHOD.

  METHOD save_data.
    IF go_grid IS BOUND.
      go_grid->check_changed_data( ).
    ENDIF.

    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out_save>).
      <ls_out_save>-vsztp    = <ls_out_save>-vsztp_disp.
      <ls_out_save>-tdarmod  = <ls_out_save>-tdarmod_disp.
      <ls_out_save>-nacha    = <ls_out_save>-nacha_disp.
      <ls_out_save>-tdocover = <ls_out_save>-tdocover_disp.
    ENDLOOP.

    DATA: lt_locked_keys TYPE STANDARD TABLE OF rstable-varkey,
          lv_success     TYPE i,
          lv_failed_lock TYPE abap_bool,
          lt_nach_new    TYPE TABLE OF nach.

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
            APPEND ls_nach_new TO lt_nach_new.
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
      MESSAGE TEXT-m03 TYPE 'E'.
      RETURN.
    ENDIF.

    IF lt_nach_new IS INITIAL.
      MESSAGE TEXT-m04 TYPE 'S'.
    ELSE.
      lv_success = lines( lt_nach_new ).

      MODIFY nach FROM TABLE @lt_nach_new.
      IF sy-subrc = 0.
        COMMIT WORK.
        LOOP AT lt_locked_keys INTO lv_key.
          CALL FUNCTION 'DEQUEUE_E_TABLE'
            EXPORTING
              mode_rstable = 'E'
              tabname      = 'NACH'
              varkey       = lv_key.
        ENDLOOP.
        LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out_saved>).
          CLEAR <ls_out_saved>-cell_colors.
          READ TABLE lt_nach_new TRANSPORTING NO FIELDS WITH KEY knumh = <ls_out_saved>-knumh.
          IF sy-subrc = 0.
            <ls_out_saved>-row_color = 'C500'.
          ELSE.
            CLEAR <ls_out_saved>-row_color.
          ENDIF.
        ENDLOOP.
        gt_original = gt_output.

        DATA(lv_msg) = CONV string( TEXT-m05 ).
        REPLACE '&1' IN lv_msg WITH |{ lv_success }|.
        MESSAGE lv_msg TYPE 'I'.

        IF go_grid IS BOUND.
          go_grid->refresh_table_display( ).
        ENDIF.
      ELSE.
        ROLLBACK WORK.
        LOOP AT lt_locked_keys INTO lv_key.
          CALL FUNCTION 'DEQUEUE_E_TABLE'
            EXPORTING
              mode_rstable = 'E'
              tabname      = 'NACH'
              varkey       = lv_key.
        ENDLOOP.
        MESSAGE TEXT-m06 TYPE 'E'.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD update_colors.
    LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      CLEAR: <ls_out>-cell_colors, <ls_out>-row_color.

      READ TABLE gt_original INTO DATA(ls_orig) WITH KEY knumh = <ls_out>-knumh.
      IF sy-subrc = 0.
        IF <ls_out>-vsztp_disp <> ls_orig-vsztp_disp.
          APPEND VALUE #( fname = 'VSZTP_DISP' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-tdarmod_disp <> ls_orig-tdarmod_disp.
          APPEND VALUE #( fname = 'TDARMOD_DISP' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-nacha_disp <> ls_orig-nacha_disp.
          APPEND VALUE #( fname = 'NACHA_DISP' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-tdocover_disp <> ls_orig-tdocover_disp.
          APPEND VALUE #( fname = 'TDOCOVER_DISP' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-anzal <> ls_orig-anzal.
          APPEND VALUE #( fname = 'ANZAL' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-pfld4 <> ls_orig-pfld4.
          APPEND VALUE #( fname = 'PFLD4' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-ldest <> ls_orig-ldest.
          APPEND VALUE #( fname = 'LDEST' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-dsnam <> ls_orig-dsnam.
          APPEND VALUE #( fname = 'DSNAM' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-dsuf1 <> ls_orig-dsuf1.
          APPEND VALUE #( fname = 'DSUF1' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-dsuf2 <> ls_orig-dsuf2.
          APPEND VALUE #( fname = 'DSUF2' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-dimme <> ls_orig-dimme.
          APPEND VALUE #( fname = 'DIMME' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.
        IF <ls_out>-delet <> ls_orig-delet.
          APPEND VALUE #( fname = 'DELET' color = VALUE #( col = 3 int = 1 ) ) TO <ls_out>-cell_colors.
        ENDIF.

        IF <ls_out>-cell_colors IS NOT INITIAL.
          <ls_out>-row_color = 'C100'.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_before_exit.
    rv_can_exit = abap_true.

    IF go_grid IS BOUND.
      go_grid->check_changed_data( ).
    ENDIF.

    DATA(lv_changed) = abap_false.
    LOOP AT gt_output INTO DATA(ls_out).
      READ TABLE gt_original INTO DATA(ls_orig) WITH KEY knumh = ls_out-knumh.
      IF sy-subrc = 0.
        DATA(ls_nach_new) = CORRESPONDING nach( ls_out ).
        DATA(ls_nach_old) = CORRESPONDING nach( ls_orig ).
        IF ls_nach_new <> ls_nach_old.
          lv_changed = abap_true.
          EXIT.
        ENDIF.
      ELSE.
        lv_changed = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_changed = abap_true.
      DATA: lv_answer TYPE c.

      CALL FUNCTION 'POPUP_TO_CONFIRM'
        EXPORTING
          titlebar              = CONV textpooltx( TEXT-q04 )
          text_question         = CONV textpooltx( TEXT-q05 )
          text_button_1         = CONV textpooltx( TEXT-b04 )
          text_button_2         = CONV textpooltx( TEXT-b05 )
          default_button        = '1'
          display_cancel_button = 'X'
        IMPORTING
          answer                = lv_answer
        EXCEPTIONS
          text_not_found        = 1
          OTHERS                = 2.

      IF sy-subrc = 0.
        CASE lv_answer.
          WHEN '1'. " Yes, save changes
            save_data( ).

            " Check if save was successful (no differences remain)
            IF gt_original = gt_output.
              rv_can_exit = abap_true.
            ELSE.
              rv_can_exit = abap_false. " Save failed, cancel exit
            ENDIF.
          WHEN '2'. " No, discard changes
            rv_can_exit = abap_true.
          WHEN 'A'. " Cancel
            rv_can_exit = abap_false.
        ENDCASE.
      ELSE.
        rv_can_exit = abap_false.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD display_alv.
    CREATE OBJECT go_grid
      EXPORTING
        i_parent = cl_gui_container=>default_screen.

    DATA: lt_dropdown TYPE lvc_t_dral.

    " Dropdown handle 1: VSZTP (Sendezeitpunkt)
    APPEND VALUE #( handle = 1 int_value = '1' value = TEXT-d11 ) TO lt_dropdown.
    APPEND VALUE #( handle = 1 int_value = '2' value = TEXT-d12 ) TO lt_dropdown.
    APPEND VALUE #( handle = 1 int_value = '3' value = TEXT-d13 ) TO lt_dropdown.
    APPEND VALUE #( handle = 1 int_value = '4' value = TEXT-d14 ) TO lt_dropdown.

    " Dropdown handle 2: TDARMOD (Archivierungsmodus)
    APPEND VALUE #( handle = 2 int_value = '1' value = TEXT-d21 ) TO lt_dropdown.
    APPEND VALUE #( handle = 2 int_value = '2' value = TEXT-d22 ) TO lt_dropdown.
    APPEND VALUE #( handle = 2 int_value = '3' value = TEXT-d23 ) TO lt_dropdown.

    " Dropdown handle 3: NACHA (Sendemedium)
    APPEND VALUE #( handle = 3 int_value = '1' value = TEXT-d31 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = '2' value = TEXT-d32 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = '4' value = TEXT-d33 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = '5' value = TEXT-d34 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = '7' value = TEXT-d35 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = '8' value = TEXT-d36 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = '9' value = TEXT-d37 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = 'A' value = TEXT-d38 ) TO lt_dropdown.
    APPEND VALUE #( handle = 3 int_value = 'I' value = TEXT-d39 ) TO lt_dropdown.

    " Dropdown handle 4: TDOCOVER (Deckblatt drucken)
    APPEND VALUE #( handle = 4 int_value = ' ' value = TEXT-d41 ) TO lt_dropdown.
    APPEND VALUE #( handle = 4 int_value = 'X' value = TEXT-d42 ) TO lt_dropdown.
    APPEND VALUE #( handle = 4 int_value = 'N' value = TEXT-d43 ) TO lt_dropdown.

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
    ls_fcat-scrtext_s = TEXT-f01.
    ls_fcat-scrtext_m = TEXT-f02.
    ls_fcat-scrtext_l = TEXT-f03.
    ls_fcat-outputlen = 50.
    ls_fcat-col_pos   = 3.
    APPEND ls_fcat TO lt_fieldcat.

    DATA(lo_struct) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( 'NACH' ) ).
    DATA: lt_dfies TYPE ddfields.
    TRY.
        lt_dfies = lo_struct->get_ddic_field_list( ).
      CATCH cx_root.
    ENDTRY.

    LOOP AT lt_fieldcat ASSIGNING FIELD-SYMBOL(<ls_fcat>).
      DATA(lv_rollname) = <ls_fcat>-rollname.
      IF lv_rollname IS INITIAL.
        READ TABLE lt_dfies INTO DATA(ls_dfies) WITH KEY fieldname = <ls_fcat>-fieldname.
        IF sy-subrc = 0.
          lv_rollname = ls_dfies-rollname.
        ENDIF.
      ENDIF.

      IF lv_rollname CP 'NA_OBS*'.
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
          <ls_fcat>-fieldname  = 'VSZTP_DISP'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '1'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 45.
          <ls_fcat>-intlen     = 50.
          CLEAR: <ls_fcat>-ref_table, <ls_fcat>-ref_field, <ls_fcat>-rollname, <ls_fcat>-domname.
        WHEN 'TDARMOD'.
          <ls_fcat>-fieldname  = 'TDARMOD_DISP'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '2'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 30.
          <ls_fcat>-intlen     = 50.
          CLEAR: <ls_fcat>-ref_table, <ls_fcat>-ref_field, <ls_fcat>-rollname, <ls_fcat>-domname.
        WHEN 'NACHA'.
          <ls_fcat>-fieldname  = 'NACHA_DISP'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '3'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 45.
          <ls_fcat>-intlen     = 50.
          CLEAR: <ls_fcat>-ref_table, <ls_fcat>-ref_field, <ls_fcat>-rollname, <ls_fcat>-domname.
        WHEN 'TDOCOVER'.
          <ls_fcat>-fieldname  = 'TDOCOVER_DISP'.
          <ls_fcat>-edit       = 'X'.
          <ls_fcat>-drdn_hndl  = '4'.
          <ls_fcat>-drdn_alias = 'X'.
          <ls_fcat>-outputlen  = 30.
          <ls_fcat>-intlen     = 50.
          CLEAR: <ls_fcat>-ref_table, <ls_fcat>-ref_field, <ls_fcat>-rollname, <ls_fcat>-domname.
        WHEN OTHERS.
          <ls_fcat>-edit = abap_false.
      ENDCASE.

      " Hide empty non-editable columns if no ALV variant is used
      IF p_vari IS INITIAL AND <ls_fcat>-edit IS INITIAL.
        DATA(lv_is_empty) = abap_true.
        LOOP AT gt_output ASSIGNING FIELD-SYMBOL(<ls_row_chk>).
          ASSIGN COMPONENT <ls_fcat>-fieldname OF STRUCTURE <ls_row_chk> TO FIELD-SYMBOL(<lv_val_chk>).
          IF sy-subrc = 0 AND <lv_val_chk> IS NOT INITIAL.
            lv_is_empty = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_is_empty = abap_true.
          <ls_fcat>-no_out = 'X'.
        ENDIF.
      ENDIF.
    ENDLOOP.

    SORT lt_fieldcat BY col_pos.
    go_grid->set_ready_for_input( 0 ).

    DATA: ls_layout TYPE lvc_s_layo.
    ls_layout-grid_title = TEXT-l01.
    ls_layout-cwidth_opt = 'X'.
    ls_layout-zebra      = 'X'.
    ls_layout-ctab_fname = 'CELL_COLORS'.
    ls_layout-info_fname = 'ROW_COLOR'.

    SET HANDLER lcl_event_handler=>handle_toolbar FOR go_grid.
    SET HANDLER lcl_event_handler=>handle_user_command FOR go_grid.
    SET HANDLER lcl_event_handler=>handle_data_changed FOR go_grid.

    go_grid->register_edit_event( i_event_id = cl_gui_alv_grid=>mc_evt_enter ).
    go_grid->register_edit_event( i_event_id = cl_gui_alv_grid=>mc_evt_modified ).

    DATA: ls_variant TYPE disvariant.
    ls_variant-report  = sy-repid.
    ls_variant-variant = p_vari.

    go_grid->set_table_for_first_display(
      EXPORTING
        is_layout                     = ls_layout
        is_variant                    = ls_variant
        i_save                        = 'A'
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
* INITIALIZATION
*---------------------------------------------------------------------*
INITIALIZATION.
  DATA: ls_default_variant TYPE disvariant.
  CLEAR ls_default_variant.
  ls_default_variant-report = sy-repid.
  CALL FUNCTION 'REUSE_ALV_VARIANT_DEFAULT_GET'
    EXPORTING
      i_save     = 'A'
    CHANGING
      cs_variant = ls_default_variant
    EXCEPTIONS
      not_found  = 1
      OTHERS     = 2.
  IF sy-subrc = 0.
    p_vari = ls_default_variant-variant.
  ENDIF.

*---------------------------------------------------------------------*
* START-OF-SELECTION
*---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_report=>run( ).

*---------------------------------------------------------------------*
* AT USER-COMMAND
*---------------------------------------------------------------------*
AT USER-COMMAND.
  CASE sy-ucomm.
    WHEN 'BACK' OR 'EXIT' OR 'CANC' OR '%EX' OR 'RW'.
      IF lcl_report=>check_before_exit( ) = abap_false.
        CLEAR sy-ucomm.
      ENDIF.
  ENDCASE.
