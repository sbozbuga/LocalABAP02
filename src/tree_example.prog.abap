*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Report ZSBTMP_USR05_TREE
*&---------------------------------------------------------------------*
*& ALV Tree and Grid Split-Screen Display for USR05 Change Logs
*& Optimized Static Version (Zero Dynamic DDIC Calls)
*&---------------------------------------------------------------------*
REPORT zsbtmp_usr05_tree02.
TYPES: ty_it_events TYPE STANDARD TABLE OF cntl_simple_event WITH DEFAULT KEY.
TYPES: ty_it_nodes TYPE STANDARD TABLE OF mtreesnode WITH DEFAULT KEY.

DATA: o_salv TYPE REF TO cl_salv_table.
DATA: it_tree_spfli TYPE STANDARD TABLE OF spfli.
DATA: it_salv_spfli TYPE STANDARD TABLE OF spfli.
DATA: it_nodes TYPE ty_it_nodes.

CLASS lcl_events DEFINITION.
  PUBLIC SECTION.
* GUI Simple Tree
    CLASS-METHODS: on_keypress FOR EVENT node_keypress OF cl_gui_simple_tree
      IMPORTING
        node_key
        key
        sender.
    CLASS-METHODS: on_selection_changed FOR EVENT selection_changed OF cl_gui_simple_tree
      IMPORTING
        node_key
        sender.
    CLASS-METHODS: on_expand_no_children FOR EVENT expand_no_children OF cl_gui_simple_tree
      IMPORTING
        node_key
        sender.
* ALV-Events für das SALV-Grid
    CLASS-METHODS: on_toolbar FOR EVENT toolbar OF cl_gui_alv_grid
      IMPORTING
        e_object
        sender.
    CLASS-METHODS: on_user_command FOR EVENT user_command OF cl_gui_alv_grid
      IMPORTING
        e_ucomm
        sender.
ENDCLASS.

CLASS lcl_events IMPLEMENTATION.
* Tastendruck
  METHOD on_keypress.
    MESSAGE |Node: { node_key } Taste: { key }| TYPE 'S'.
  ENDMETHOD.
* Klick auf ein aktives Baumelement
  METHOD on_selection_changed.
* Element in der Nodes-Tabelle lesen
    ASSIGN it_nodes[ node_key = node_key ] TO FIELD-SYMBOL(<fs_node>).

* iTab für SALV-Table neu aufbauen
    CLEAR: it_salv_spfli.

    LOOP AT it_tree_spfli ASSIGNING FIELD-SYMBOL(<fs_line>) WHERE carrid = <fs_node>-text.
      APPEND <fs_line> TO it_salv_spfli.
    ENDLOOP.

* SALV-Table neu anzeigen
    o_salv->refresh( ).
  ENDMETHOD.
* bei Expandierung eines Baumelements ohne Unterelemente
  METHOD on_expand_no_children.
    MESSAGE |Node: { node_key }| TYPE 'S'.
  ENDMETHOD.

* Toolbar-Buttons hinzufügen:
* butn_type   Bezeichung
* 0           Button (normal)
* 1           Menü + Defaultbutton
* 2           Menü
* 3           Separator
* 4           Radiobutton
* 5           Auswahlknopf (Checkbox)
* 6           Menüeintrag
  METHOD on_toolbar.
* Separator hinzufügen
    APPEND VALUE #( butn_type = 3 ) TO e_object->mt_toolbar.
* Edit-Button hinzufügen
    APPEND VALUE #( butn_type = 5 text = 'Daten anzeigen' icon = icon_icon_list function = 'SHOW_DATA' quickinfo = 'Daten anzeigen' disabled = ' ' ) TO e_object->mt_toolbar.
  ENDMETHOD.
* Benutzerkommando (Button-Klick)
  METHOD on_user_command.
    CASE e_ucomm.
      WHEN 'SHOW_DATA'.
        DATA: lv_row TYPE i. " Zeile auf Grid
        DATA: lv_value TYPE char255. " Wert
        DATA: lv_col TYPE i. " Spalte auf Grid
        DATA: lv_row_id TYPE lvc_s_row. " Zeilen-Id
        DATA: lv_col_id TYPE lvc_s_col. " Spalten-Id
        DATA: lv_row_no TYPE lvc_s_roid. " Numerische Zeilen ID

        sender->get_current_cell( IMPORTING
                                    e_row = lv_row
                                    e_value = lv_value
                                    e_col = lv_col
                                    es_row_id = lv_row_id
                                    es_col_id = lv_col_id
                                    es_row_no = lv_row_no ).

        MESSAGE |Zeile: { lv_row }, Spalte: { lv_col }, Wert: { lv_value }, Spaltenname: { lv_col_id-fieldname }| TYPE 'S'.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.

  SELECT * INTO TABLE it_tree_spfli FROM spfli.

* Splitter auf screen0 erzeugen
  DATA(o_split) = NEW cl_gui_splitter_container( parent = cl_gui_container=>screen0
                                                 no_autodef_progid_dynnr = abap_true
                                                 rows = 1
                                                 columns = 2 ).

* Breite in % (linke Spalte für den Tree)
  o_split->set_column_width( id = 1 width = 15 ).

* linken und rechten Splitcontainer holen
  DATA(o_spl_left) = o_split->get_container( row = 1 column = 1 ).
  DATA(o_spl_right) = o_split->get_container( row = 1 column = 2 ).

  TRY.
* Tree-Objekt erzeugen
      DATA(o_tree) = NEW cl_gui_simple_tree( parent = o_spl_left
                                             node_selection_mode = cl_gui_simple_tree=>node_sel_mode_single ).


* Eventtypten müssen gesondert registriert werden
      DATA(it_events) = VALUE ty_it_events( ( eventid = cl_gui_simple_tree=>eventid_node_keypress
                                              appl_event = abap_true )
                                            ( eventid = cl_gui_simple_tree=>eventid_selection_changed
                                              appl_event = abap_true )
                                            ( eventid = cl_gui_simple_tree=>eventid_expand_no_children
                                              appl_event = abap_true ) ).

      o_tree->set_registered_events( events = it_events ).

      o_tree->add_key_stroke( cl_gui_simple_tree=>key_enter ).

* Events registrieren
      SET HANDLER lcl_events=>on_keypress FOR o_tree.
      SET HANDLER lcl_events=>on_selection_changed FOR o_tree.
      SET HANDLER lcl_events=>on_expand_no_children FOR o_tree.

* Root-Node einfügen
      it_nodes = VALUE #( ( node_key  = 'ROOT'           " Node-Bezeichner
                            relatship = cl_gui_simple_tree=>relat_last_child
                            disabled  = abap_true
                            isfolder  = abap_true        " Typ Ordner für Root-Element
                            n_image   = icon_folder      " Icon Ordner
                            exp_image = icon_open_folder " Icon geöffneter Ordner
                            style     = cl_gui_simple_tree=>style_default
                            text      = 'Airlines' ) ).

* Childs an Root-Node anhängen
      LOOP AT it_tree_spfli ASSIGNING FIELD-SYMBOL(<fs_line>).
* bei Änderung der carrid neue carrid als Child anhängen
        AT NEW carrid.
          APPEND VALUE #( node_key  = |NODE{ sy-tabix }| " eindeutiger Node-Bezeichner
                          relatship = cl_gui_simple_tree=>relat_last_child
                          relatkey  = 'ROOT'             " an ROOT-Element anhängen
                          style     = cl_gui_simple_tree=>style_intensified
                          text      = |{ <fs_line>-carrid }| ) TO it_nodes.
        ENDAT.
      ENDLOOP.

* Nodes im Baum einfügen
      o_tree->add_nodes( table_structure_name = 'MTREESNODE' " Typ muss gleich mit Zeilentyp von ty_it_nodes sein
                         node_table           = it_nodes ).

* Root-Nodes des Trees expandieren
      o_tree->expand_root_nodes( ).

* leeres SALV-Grid erzeugen
      cl_salv_table=>factory( EXPORTING
                                r_container    = o_spl_right
                              IMPORTING
                                r_salv_table   = o_salv
                              CHANGING
                                t_table        = it_salv_spfli ).

      o_salv->get_display_settings( )->set_striped_pattern( abap_true ).
      o_salv->get_columns( )->set_optimize( abap_true ).
      o_salv->get_functions( )->set_all( ).
      o_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).
      o_salv->display( ).

* Trick: Aus dem Split-Container rechts das Grid-Objekt holen und nach cl_gui_alv_grid casten
      READ TABLE o_spl_right->children INDEX 1 ASSIGNING FIELD-SYMBOL(<child>).
      IF <child> IS ASSIGNED.
        DATA(o_alv_grid) = CAST cl_gui_alv_grid( <child> ).

* Eventhandler registrieren
        SET HANDLER lcl_events=>on_toolbar FOR o_alv_grid.
        SET HANDLER lcl_events=>on_user_command FOR o_alv_grid.
      ENDIF.

    CATCH cx_root INTO DATA(e_text).
      WRITE: / e_text->get_text( ).
  ENDTRY.

* leere Toolbar ausblenden
  cl_abap_list_layout=>suppress_toolbar( ).

* cl_gui_container=>screen0 erzwingen
  WRITE space.