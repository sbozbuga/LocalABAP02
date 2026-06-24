*&---------------------------------------------------------------------*
*& Report  YUSR05_PROTOKOLL
*&
*&---------------------------------------------------------------------*
*& Auswertung Tabellenänderungen zu USR05
*& 1909-254 Darstellung der Änderungen in den User Parametern
*&
*&---------------------------------------------------------------------*

REPORT  zsbtmp_yusr05_protokoll.

TYPE-POOLS: abap.

TABLES: dbtablog,      "DBTABLOG
        usr05.

DATA:       gv_uservariant_exist TYPE abap_bool.

*%%%%%%%%%%%%%%%%%%%%%%%%%% Selektionsbild %%%%%%%%%%%%%%%%%%%%%%%%%%%%*
SELECTION-SCREEN : BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
SELECT-OPTIONS   :   s_bname        FOR usr05-bname.
SELECTION-SCREEN : END   OF BLOCK b01.

"---Auswertezeitraum
SELECTION-SCREEN BEGIN OF BLOCK interv WITH FRAME TITLE TEXT-001.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(24) FOR FIELD dbeg.        "UFi2337770/2004b
PARAMETERS: dbeg TYPE tlog_begdat.                          "1. Tag.
SELECTION-SCREEN COMMENT 40(24) FOR FIELD tbeg.
PARAMETERS: tbeg TYPE tlog_begtime.      "UFi2337770/2004e"Anfangszeit
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(24) FOR FIELD dend.        "UFi2337770/2004b
PARAMETERS: dend TYPE tlog_enddat DEFAULT sy-datum.         "letzer Tag
SELECTION-SCREEN COMMENT 40(24) FOR FIELD tend.
PARAMETERS: tend TYPE tlog_endtime DEFAULT sy-uzeit.
*                                          "UFi2337770/2004e"Schlußzeit
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK interv.

SELECTION-SCREEN : BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-b02.
SELECT-OPTIONS   :   s_usera        FOR dbtablog-username,
                     s_tcode        FOR dbtablog-tcode.
SELECTION-SCREEN : END   OF BLOCK b02.


*--- Variante einblenden
SELECTION-SCREEN : BEGIN OF BLOCK b03 WITH FRAME TITLE TEXT-b03.
PARAMETERS : pa_vari LIKE disvariant-variant.
SELECTION-SCREEN : END   OF BLOCK b03.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR pa_vari.
  PERFORM f4_layouts USING if_salv_c_layout=>restrict_none CHANGING pa_vari.

INITIALIZATION.
  dbeg = sy-datum - 30.

*%%%%%%%%%%%%%%%%%%%%%%%%%% Klassen        %%%%%%%%%%%%%%%%%%%%%%%%%%%%*

*----------------------------------------------------------------------*
*       CLASS lcl_yle01 DEFINITION
*----------------------------------------------------------------------*
*
*----------------------------------------------------------------------*
CLASS lcl_usr05 DEFINITION.

  PUBLIC    SECTION.
    CLASS-METHODS : main.

  PRIVATE   SECTION.
    TYPES:
      BEGIN OF tys_usrpar,
        bname TYPE xubname,
        parid TYPE memoryid,
        parva TYPE xuvalue,
      END OF tys_usrpar,
      tyt_usrpar TYPE HASHED TABLE OF tys_usrpar WITH UNIQUE KEY bname parid,

      BEGIN OF tys_usr05,
        logdate  TYPE sydats,  "aus DBTABLOG
        logtime  TYPE sytime,
        username TYPE xubname,
        tcode    TYPE tcode,
        optype   TYPE optype,

        mandt    TYPE mandt,                                "aus USR05
        bname    TYPE xubname,
        parid    TYPE memoryid,
        parva    TYPE xuvalue,
      END OF tys_usr05,
      tyt_usr05 TYPE STANDARD TABLE OF tys_usr05,

      BEGIN OF tys_usr05_change,
        logdate   TYPE p01c_rcdat,  "Änderungsdatum
        logtime   TYPE emg_euzeit,  "angelegt
        username  TYPE /hoag/b_upduser,  "geändert durch
        tcode     TYPE tcode,
        optype    TYPE optype,

        mandt     TYPE mandt,                               "aus USR05
        bname     TYPE xubname,
        parid     TYPE memoryid,
        parva_old TYPE zdxuvalueold,
        parva_new TYPE zdxuvaluenew,

      END OF tys_usr05_change,
      tyt_usr05_change TYPE STANDARD TABLE OF tys_usr05_change,

      BEGIN OF tys_usr01,
        bname TYPE xubname,
      END OF tys_usr01,
      tyt_usr01   TYPE HASHED TABLE OF tys_usr01 WITH UNIQUE KEY bname,

      tyt_datalog TYPE STANDARD TABLE OF dbtablog.

    CLASS-DATA:
      gt_usrpar       TYPE tyt_usrpar,
      gt_usr05        TYPE tyt_usr05,
      gt_usr05_change TYPE tyt_usr05_change.


    CLASS-METHODS :
      select_datalog,
      determine_changes,
      select_merge_usrpar,
      remove_upd_no_change,

      show_list.

ENDCLASS.                    "lcl_usr05 DEFINITION
*----------------------------------------------------------------------*
*       CLASS lcl_yle01 IMPLEMENTATION
*----------------------------------------------------------------------*
*
*----------------------------------------------------------------------*
CLASS lcl_usr05 IMPLEMENTATION.

  METHOD main.

    ycl_base=>write_replog( ).

    select_datalog( ).
    determine_changes( ).
    select_merge_usrpar( ).

    remove_upd_no_change( ).

    show_list( ).

  ENDMETHOD.                    "main


*----------------------------------------------------------------------*
* Userparameter aus USR05 auslesen
* Grundlage sind Daten aus gt_usr05_change
*----------------------------------------------------------------------*
  METHOD select_merge_usrpar.

    DATA:
      lv_parva        TYPE xuvalue,
      lt_usr05_change TYPE tyt_usr05_change.

    FIELD-SYMBOLS:
      <ls_usrpar>         LIKE LINE OF gt_usrpar,
      <ls_usr05_change_l> LIKE LINE OF gt_usr05_change,
      <ls_usr05_change>   LIKE LINE OF gt_usr05_change.


    CHECK NOT gt_usr05_change[] IS INITIAL.

    "user und Parameter eindeutig
    lt_usr05_change[] = gt_usr05_change[].
    SORT lt_usr05_change BY bname parid.
    DELETE ADJACENT DUPLICATES FROM lt_usr05_change COMPARING bname parid.


    SELECT * FROM usr05
      INTO CORRESPONDING FIELDS OF TABLE gt_usrpar
      FOR ALL ENTRIES IN lt_usr05_change
      WHERE bname = lt_usr05_change-bname
        AND parid = lt_usr05_change-parid.

    SORT gt_usr05_change BY bname   ASCENDING
                            parid   ASCENDING
                            logdate DESCENDING
                            logtime DESCENDING.

    "pro Benutzer und PArameter verarbeiten
    LOOP AT lt_usr05_change ASSIGNING <ls_usr05_change_l>.
      CLEAR: lv_parva.
      LOOP AT gt_usr05_change ASSIGNING <ls_usr05_change> WHERE bname = <ls_usr05_change_l>-bname
                                                            AND parid = <ls_usr05_change_l>-parid.
        IF <ls_usr05_change>-optype = 'U'.
          IF lv_parva IS INITIAL.
            "erstes Mal; dann aktuellen Wert holen; ist neuester Wert
            READ TABLE gt_usrpar ASSIGNING <ls_usrpar> WITH TABLE KEY bname = <ls_usr05_change>-bname
                                                                      parid = <ls_usr05_change>-parid.
            IF sy-subrc = 0.
              "aktueller Wert aus Userparameter
              <ls_usr05_change>-parva_new = <ls_usrpar>-parva.

            ENDIF.
          ELSE.
            IF <ls_usr05_change>-parva_new IS INITIAL.
              <ls_usr05_change>-parva_new = lv_parva.
            ENDIF.

          ENDIF.
          lv_parva = <ls_usr05_change>-parva_old.
        ENDIF.
      ENDLOOP.  "LOOP AT gt_usr05_change
    ENDLOOP.

  ENDMETHOD.                    "select_usrpar

*----------------------------------------------------------------------*
* Es kommen noch Einträge vor mit U und Wert alt = neu; diese raus
*----------------------------------------------------------------------*
  METHOD remove_upd_no_change.

    FIELD-SYMBOLS:
      <ls_usr05_change>   LIKE LINE OF gt_usr05_change.

    LOOP AT gt_usr05_change ASSIGNING <ls_usr05_change> WHERE optype = 'U'.
      IF <ls_usr05_change>-parva_new = <ls_usr05_change>-parva_old.
        DELETE gt_usr05_change.
      ENDIF.
    ENDLOOP.  "LOOP AT gt_usr05_change

  ENDMETHOD.                 "remove_upd_no_change
*----------------------------------------------------------------------*
* Datalog auswerten und Feldinhalte auslesen
*----------------------------------------------------------------------*
  METHOD select_datalog.

    DATA:
      lo_conv    TYPE REF TO cl_abap_conv_in_ce,
      lt_datalog TYPE tyt_datalog,
      lt_usr01   TYPE tyt_usr01.


    FIELD-SYMBOLS:
      <ls_usr05>   TYPE tys_usr05,
      <ls_datalog> TYPE dbtablog,
      <ls_usr01>   TYPE tys_usr01.

    SELECT * FROM dbtablog
      INTO TABLE lt_datalog
      WHERE ( logdate > dbeg OR ( logdate = dbeg AND logtime >= tbeg ) )
        AND ( logdate < dend OR ( logdate = dend AND logtime <= tend ) )
        AND tcode    IN s_tcode  "'SU01'   SU01, su3, ... auch diverse Programme
        AND username IN s_usera
        AND tabname  =  'USR05'.

    LOOP AT   lt_datalog ASSIGNING   <ls_datalog>.

      INSERT INITIAL LINE INTO TABLE gt_usr05 ASSIGNING <ls_usr05>.

      "fixe Werte zuweisen
      <ls_usr05>-logdate  = <ls_datalog>-logdate.
      <ls_usr05>-logtime  = <ls_datalog>-logtime.
      <ls_usr05>-username = <ls_datalog>-username.
      <ls_usr05>-tcode    = <ls_datalog>-tcode.
      <ls_usr05>-optype   = <ls_datalog>-optype.

      "restliche Werte aus logdate ermitteln
      CALL METHOD cl_abap_conv_in_ce=>create
        EXPORTING
          encoding    = '4102'   "unicode
          endian      = 'B'
          ignore_cerr = 'X'
          replacement = '#'
          input       = <ls_datalog>-logdata
        RECEIVING
          conv        = lo_conv.
      CALL METHOD lo_conv->read
        EXPORTING
          n    = 3
        IMPORTING
          data = <ls_usr05>-mandt.

      CALL METHOD lo_conv->read
        EXPORTING
          n    = 12
        IMPORTING
          data = <ls_usr05>-bname.

      CALL METHOD lo_conv->read
        EXPORTING
          n    = 20
        IMPORTING
          data = <ls_usr05>-parid.

      CALL METHOD lo_conv->read
        EXPORTING
          n    = 40
        IMPORTING
          data = <ls_usr05>-parva.

    ENDLOOP.

    "Einbschränkung auf Bestimme Benutzer
    DELETE gt_usr05 WHERE NOT bname IN s_bname.

    "nicht vorhandene Benutzer raus
    SELECT bname
      FROM usr01
      INTO TABLE lt_usr01.
    LOOP AT gt_usr05 ASSIGNING <ls_usr05>.
      READ TABLE lt_usr01 ASSIGNING <ls_usr01> WITH TABLE KEY bname = <ls_usr05>-bname.
      IF sy-subrc <> 0.
        DELETE gt_usr05.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.                    "select_datalog

*----------------------------------------------------------------------*
* Pro Datum, Uhrzeit, User Änderungen ermitteln
*----------------------------------------------------------------------*
  METHOD determine_changes.

    DATA:
      lt_usr05_chg TYPE tyt_usr05,
      lt_usr05_del TYPE tyt_usr05,
      lt_usr05_upd TYPE tyt_usr05,
      lt_usr05_ins TYPE tyt_usr05,

      lv_found     TYPE abap_bool,
      lv_logtime   TYPE sytime.

    FIELD-SYMBOLS:
      <ls_usr05_chg>    TYPE tys_usr05,
      <ls_usr05>        TYPE tys_usr05,
      <ls_usr05a>       TYPE tys_usr05,
      <ls_usr05b>       TYPE tys_usr05,
      <ls_usr05_change> TYPE tys_usr05_change.


    "eindeutig pro Datum/Uhrzeit/geänderer Benutzer
    lt_usr05_chg[] = gt_usr05[].
    SORT lt_usr05_chg BY logdate logtime mandt bname.
    DELETE ADJACENT DUPLICATES FROM lt_usr05_chg COMPARING logdate logtime mandt bname.

    LOOP AT lt_usr05_chg ASSIGNING <ls_usr05_chg>.
      CLEAR: lt_usr05_del[], lt_usr05_ins[].
      "separieren der Inserts und Delete
      LOOP AT gt_usr05 ASSIGNING <ls_usr05> WHERE logdate = <ls_usr05_chg>-logdate
                                              AND logtime = <ls_usr05_chg>-logtime
                                              AND mandt   = <ls_usr05_chg>-mandt
                                              AND bname   = <ls_usr05_chg>-bname.
        "gibt I, U oder D
        CASE <ls_usr05>-optype.
          WHEN 'I'.
            INSERT INITIAL LINE INTO TABLE lt_usr05_ins ASSIGNING <ls_usr05a>.
          WHEN 'U'.
            INSERT INITIAL LINE INTO TABLE lt_usr05_upd ASSIGNING <ls_usr05a>.
          WHEN 'D'.
            INSERT INITIAL LINE INTO TABLE lt_usr05_del ASSIGNING <ls_usr05a>.
        ENDCASE.

        <ls_usr05a> = <ls_usr05>.
      ENDLOOP.

      IF lt_usr05_del[] IS INITIAL AND lt_usr05_ins[] IS INITIAL AND lt_usr05_upd[] IS INITIAL.
        "SOnderfall für + 1 s
        CONTINUE.
      ENDIF.

      "Problem genau eine S danach
      lv_logtime =  <ls_usr05_chg>-logtime + 1.
      LOOP AT gt_usr05 ASSIGNING <ls_usr05> WHERE logdate = <ls_usr05_chg>-logdate
                                          AND logtime = lv_logtime
                                          AND mandt   = <ls_usr05_chg>-mandt
                                          AND bname   = <ls_usr05_chg>-bname.
        "gibt bei dem Typ lediglich I oder D
        "gibt I, U oder D
        CASE <ls_usr05>-optype.
          WHEN 'I'.
            INSERT INITIAL LINE INTO TABLE lt_usr05_ins ASSIGNING <ls_usr05a>.
          WHEN 'U'.
            INSERT INITIAL LINE INTO TABLE lt_usr05_upd ASSIGNING <ls_usr05a>.
          WHEN 'D'.
            INSERT INITIAL LINE INTO TABLE lt_usr05_del ASSIGNING <ls_usr05a>.
        ENDCASE.
        <ls_usr05a> = <ls_usr05>.
        "Aus Originaltabelle rausnehmen, da sonst doppelt
        DELETE gt_usr05.
      ENDLOOP.

      "kann auch mehrfach pro Uhrzeit auftreten
      SORT lt_usr05_ins.
      DELETE ADJACENT DUPLICATES FROM lt_usr05_ins.
      SORT lt_usr05_del.
      DELETE ADJACENT DUPLICATES FROM lt_usr05_del.
      SORT lt_usr05_upd.
      DELETE ADJACENT DUPLICATES FROM lt_usr05_upd.

      "Änderungen ermitteln zunächst neue prüfen
      LOOP AT lt_usr05_ins ASSIGNING <ls_usr05a>.
        lv_found = abap_false.
        LOOP AT lt_usr05_del ASSIGNING <ls_usr05b> WHERE parid = <ls_usr05a>-parid.
          lv_found = abap_true.
          IF <ls_usr05a>-parva = <ls_usr05b>-parva.
            "keine Änderung

          ELSE.
            INSERT INITIAL LINE INTO TABLE gt_usr05_change ASSIGNING <ls_usr05_change>.
            MOVE-CORRESPONDING <ls_usr05b> TO <ls_usr05_change>.
            <ls_usr05_change>-parva_old = <ls_usr05b>-parva.
            <ls_usr05_change>-parva_new = <ls_usr05a>-parva.
          ENDIF.
          DELETE lt_usr05_del.  "Eintrag raus
        ENDLOOP.
        IF lv_found = abap_false.
          "neuer Eintrag
          INSERT INITIAL LINE INTO TABLE gt_usr05_change ASSIGNING <ls_usr05_change>.
          MOVE-CORRESPONDING <ls_usr05a> TO <ls_usr05_change>.
          <ls_usr05_change>-parva_new = <ls_usr05a>-parva.
        ENDIF.
        DELETE lt_usr05_ins.
      ENDLOOP.

      "Änderungen ermitteln zunächst neue prüfen
      LOOP AT lt_usr05_upd ASSIGNING <ls_usr05a>.
        INSERT INITIAL LINE INTO TABLE gt_usr05_change ASSIGNING <ls_usr05_change>.
        MOVE-CORRESPONDING <ls_usr05a> TO <ls_usr05_change>.
        <ls_usr05_change>-parva_old = <ls_usr05a>-parva.
      ENDLOOP.


      "falls noch Einträge in lt_usr05_del so sind die gelöscht.
      LOOP AT lt_usr05_del ASSIGNING <ls_usr05b>.
        INSERT INITIAL LINE INTO TABLE gt_usr05_change ASSIGNING <ls_usr05_change>.
        MOVE-CORRESPONDING <ls_usr05b> TO <ls_usr05_change>.
        <ls_usr05_change>-parva_old = <ls_usr05b>-parva.
      ENDLOOP.

    ENDLOOP. "AT lt_usr05_chg


  ENDMETHOD.                    "determine_changes

*----------------------------------------------------------------------*
* ALV-Liste
*----------------------------------------------------------------------*
  METHOD show_list.

    DATA: lr_salv       TYPE REF TO cl_salv_table,
          lr_func       TYPE REF TO cl_salv_functions_list,
          lr_layout     TYPE REF TO cl_salv_layout,
          ls_key        TYPE salv_s_layout_key,
          lr_columns    TYPE REF TO cl_salv_columns,
          lr_column     TYPE REF TO cl_salv_column_table,
          lr_columns_t  TYPE REF TO cl_salv_columns_table,
          lr_events     TYPE REF TO cl_salv_events_table,
          lr_header     TYPE REF TO cl_salv_form_header_info,
          lr_display    TYPE REF TO cl_salv_display_settings,
          lr_selections TYPE REF TO cl_salv_selections,
          lv_text       TYPE text10,
          lv_title      TYPE string,
          lv_lines      TYPE i.

    lv_lines = lines( gt_usr05_change ).

    TRY.
        CALL METHOD cl_salv_table=>factory
          IMPORTING
            r_salv_table = lr_salv
          CHANGING
            t_table      = gt_usr05_change.
      CATCH cx_salv_msg.                                "#EC NO_HANDLER
    ENDTRY.

    "Sichern Layout-Einstellungen
    lr_layout = lr_salv->get_layout( ).

    ls_key-report = sy-repid.
    lr_layout->set_key( ls_key ).
    lr_layout->set_save_restriction( if_salv_c_layout=>restrict_none ).
    lr_layout->set_default( abap_true ).

    IF NOT pa_vari IS INITIAL.
      lr_layout->set_initial_layout( pa_vari ).
    ENDIF.


    CALL METHOD lr_salv->get_functions
      RECEIVING
        value = lr_func.
    lr_func->set_all( abap_true ).

    "Zebra-Muster
    lr_display = lr_salv->get_display_settings( ).
    lr_display->set_striped_pattern( abap_true ).

    lr_columns = lr_salv->get_columns( ).
    lr_columns->set_optimize( abap_true ).


    "Header
    WRITE lv_lines TO lv_text LEFT-JUSTIFIED.

    CONCATENATE 'Anzahl Datensätze:'(013) lv_text INTO lv_title
      SEPARATED BY space.

    CREATE OBJECT lr_header
      EXPORTING
        text = lv_title.

    lr_salv->set_top_of_list( lr_header ).


    lr_salv->display( ).

  ENDMETHOD.                    "show_list

ENDCLASS.                    "lcl_usr05  IMPLEMENTATION

INITIALIZATION.
  PERFORM standard_user_variant_fill CHANGING gv_uservariant_exist.
  IF gv_uservariant_exist = abap_false.
    PERFORM get_default_layout USING if_salv_c_layout=>restrict_none CHANGING pa_vari.
  ENDIF.

START-OF-SELECTION.

*--- Selektion und Darstellung der Daten
  CALL METHOD lcl_usr05=>main( ).


*&---------------------------------------------------------------------*
*&      Form  f4_layouts
*&---------------------------------------------------------------------*
* §4.5 F4 Layouts
*      cl_salv_layout provides a method for handling the f4 help of the
*      layouts for the specified layout key. It is also possible to use
*      the static class cl_salv_layout_service.
*----------------------------------------------------------------------*
FORM f4_layouts USING    p_restrict TYPE salv_de_layout_restriction
                CHANGING p_layout   TYPE disvariant-variant.

  DATA: ls_layout TYPE salv_s_layout_info,
        ls_key    TYPE salv_s_layout_key.

  ls_key-report = sy-repid.

  ls_layout = cl_salv_layout_service=>f4_layouts(
    s_key    = ls_key
    restrict = p_restrict ).

  p_layout = ls_layout-layout.

ENDFORM.                    " f4_layouts
*&---------------------------------------------------------------------*
*&      Form  GET_DEFAULT_LAYOUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      <--P_P_LAY06  text
*----------------------------------------------------------------------*
FORM get_default_layout USING    i_restrict TYPE salv_de_layout_restriction
                        CHANGING p_layout   TYPE disvariant-variant.

  DATA: ls_layout   TYPE salv_s_layout_info,
        ls_key      TYPE salv_s_layout_key,
        lv_restrict TYPE salv_de_layout_restriction  VALUE if_salv_c_layout=>restrict_none.

  ls_key-report = sy-repid.

  ls_layout = cl_salv_layout_service=>get_default_layout(
    s_key    = ls_key
    restrict = lv_restrict ).

  p_layout = ls_layout-layout.
ENDFORM.                    " GET_DEFAULT_LAYOUT

*&---------------------------------------------------------------------*
*&      Form  standard_user_variant_fill
*&---------------------------------------------------------------------*
*       Vorbelegung der Selektionen mit einem USER-DEFAULT
*       Dazu muss eine Variante mit dem Namen U_<sy-uname> angelegt werden
*----------------------------------------------------------------------*
FORM standard_user_variant_fill CHANGING cv_variant_exist TYPE abap_bool.

  DATA:
    lv_subrc   LIKE sy-subrc,
    lv_repid   LIKE rsvar-report,
    lv_variant LIKE rsvar-variant.

  cv_variant_exist = abap_false.

* Prüfen, ob es eine User-spezifische Variante zu dem aktuellen Report
* exisitiert
  lv_repid = sy-repid.
  CONCATENATE 'U_' sy-uname
         INTO lv_variant.
  CALL FUNCTION 'RS_VARIANT_EXISTS'
    EXPORTING
      report  = lv_repid
      variant = lv_variant
    IMPORTING
      r_c     = lv_subrc.

  CHECK lv_subrc IS INITIAL.

  cv_variant_exist = 'X'.
* Aufruf der vorhandenen User-Variante für das Selektions-Bild
  CALL FUNCTION 'RS_SUPPORT_SELECTIONS'
    EXPORTING
      report               = lv_repid
      variant              = lv_variant
    EXCEPTIONS
      variant_not_existent = 0
      variant_obsolete     = 0.

ENDFORM.                    "standard_user_variant_fill
