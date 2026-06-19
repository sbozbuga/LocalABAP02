*----------------------------------------------------------------------*
***INCLUDE LTXW0E1F32.                  "new with note 2246560
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*&      Form  DBTABLOG_CONVERT
*&---------------------------------------------------------------------*
*       convert the LOGDATA of DBTABLOG in table structure
*----------------------------------------------------------------------*
FORM dbtablog_convert USING is_dbtablog TYPE dbtablog
                            id_tabname  TYPE tabname
                   CHANGING cr_tab      TYPE REF TO data.

  STATICS: sd_tabname     TYPE tabname,
           st_tab_detail  TYPE tt_tabdetails,
           st_spec_tabkey TYPE tt_special_tabkey,
           sr_converter   TYPE REF TO cl_abap_conv_in_ce,
           st_codepages   TYPE tt_codepages,
           sd_char_size   TYPE i,
           sd_codepage    TYPE abap_encod.

  DATA: ld_crtimestmp TYPE crstamp.

  FIELD-SYMBOLS: <ls_tab>        TYPE any,
                 <ld_field>      TYPE any,
                 <ls_tab_detail> TYPE ts_tabdetails.

  IF sd_tabname <> id_tabname.
*   initialize for different TABNAMES
    sd_tabname = id_tabname.
    REFRESH: st_tab_detail,
             st_spec_tabkey.
    CLEAR: sr_converter.
    PERFORM codepage_init CHANGING st_codepages
                                   sd_char_size
                                   sd_codepage.
  ENDIF.

  IF NOT cr_tab IS BOUND..
    CREATE DATA cr_tab TYPE (id_tabname).
  ENDIF.
  ASSIGN cr_tab->* TO <ls_tab>.
  CLEAR <ls_tab>.

  PERFORM nametab_get USING id_tabname
                   CHANGING st_tab_detail
                            st_spec_tabkey.
  PERFORM crtimestmp_get USING is_dbtablog-logdate
                               is_dbtablog-logtime
                               is_dbtablog-tabname
                               st_tab_detail
                      CHANGING ld_crtimestmp.
  PERFORM conversion_init USING is_dbtablog-logdate
                                is_dbtablog-logtime
                                is_dbtablog-logdata
                                is_dbtablog-versno
                                st_codepages
                                sd_codepage
                       CHANGING sr_converter.

* now do conversion for the fields of the structure
  LOOP AT st_tab_detail ASSIGNING <ls_tab_detail>
                        WHERE tabname    = id_tabname
                          AND crtimestmp = ld_crtimestmp
                        "No .INCLUDE's should be evaluated
                          AND datatype <> 'STRU'
                          AND NOT inttype IS INITIAL.
    ASSIGN COMPONENT <ls_tab_detail>-fieldname
                        OF STRUCTURE <ls_tab> TO <ld_field>.
    CHECK sy-subrc = 0 AND <ld_field> IS ASSIGNED.
    PERFORM field_convert USING is_dbtablog
                                <ls_tab_detail>
                                sr_converter
                                sd_char_size
                       CHANGING <ld_field>.
  ENDLOOP.

ENDFORM.                    "dbtablog_convert
*&---------------------------------------------------------------------*
*&      Form  NAMETAB_GET
*&---------------------------------------------------------------------*
*       get DDIC informations for DB table
*----------------------------------------------------------------------*
FORM nametab_get USING id_tabname     TYPE tabname
              CHANGING ct_tab_detail  TYPE tt_tabdetails
                       ct_spec_tabkey TYPE tt_special_tabkey.

  DATA: lt_dfies   TYPE STANDARD TABLE OF dfies,
        lt_history TYPE STANDARD TABLE OF ddnthist INITIAL SIZE 20.

  DATA: ld_crtimestmp TYPE crstamp.

  FIELD-SYMBOLS: <ls_history> TYPE ddnthist.

  "Exit if table details are already available
  READ TABLE ct_tab_detail WITH KEY tabname = id_tabname
                           BINARY SEARCH
                           TRANSPORTING NO FIELDS.
  IF sy-subrc EQ 0.
    RETURN.
  ENDIF.

  "Get nametab history
  CALL FUNCTION 'DD_NTAB_HIST_GET'
    EXPORTING
      tabname           = id_tabname
    TABLES
      nthist            = lt_history
    EXCEPTIONS
      not_found         = 1
      invalid_parameter = 2
      OTHERS            = 3.
  " Are there history-entries?
  " yes -> extract info of them with DD_INT_NAMETAB_TO_DFIES
  " and convert it to DFIES
  " no ->  get it from DDIF_FIELDINFO_GET
  IF sy-subrc EQ 0.
    LOOP AT lt_history ASSIGNING <ls_history>.
      CALL FUNCTION 'DD_INT_NAMETAB_TO_DFIES'
        TABLES
          x031l_tab     = <ls_history>-fields
          dfies_tab     = lt_dfies
        EXCEPTIONS
          illegal_input = 1
          OTHERS        = 2.
      IF sy-subrc EQ 0.
        PERFORM dfies_get USING lt_dfies
                                <ls_history>-crtimestmp
                       CHANGING ct_tab_detail
                                ct_spec_tabkey.
      ELSE.
        MESSAGE x016(xw).
      ENDIF.
    ENDLOOP.
  ELSE.
    CALL FUNCTION 'DDIF_FIELDINFO_GET'
      EXPORTING
        tabname        = id_tabname
        langu          = sy-langu
        all_types      = abap_true
      TABLES
        dfies_tab      = lt_dfies
      EXCEPTIONS
        not_found      = 1
        internal_error = 2
        OTHERS         = 3.
    IF sy-subrc EQ 0.
      "Set the timestamp of the nametab to actual value
      ld_crtimestmp = gc_crstamp_infinit.
      PERFORM dfies_get USING lt_dfies
                              ld_crtimestmp
                     CHANGING ct_tab_detail
                              ct_spec_tabkey.
    ENDIF.
  ENDIF.
  "Sort lt_tab_details
  SORT ct_tab_detail BY tabname crtimestmp offset.

ENDFORM.                    "nametab_get
*&---------------------------------------------------------------------*
*&      Form  DFIES_GET
*&---------------------------------------------------------------------*
*       convert DDIC information to internal used format
*----------------------------------------------------------------------*
FORM dfies_get USING it_dfies       TYPE dfies_table
                     id_crtimestmp  TYPE crstamp
            CHANGING ct_tab_detail  TYPE tt_tabdetails
                     ct_spec_tabkey TYPE tt_special_tabkey.

  DATA: lt_dfies TYPE STANDARD TABLE OF dfies.

  DATA: ls_dfies          TYPE dfies,
        ls_special_tabkey TYPE ts_special_tabkey,
        ls_tabdetails     TYPE ts_tabdetails.

  DATA: ld_keylen         TYPE i,
        ld_special_tabkey TYPE c.

  lt_dfies = it_dfies.

  CLEAR ls_tabdetails.

  "Compute length of table key
  LOOP AT lt_dfies INTO ls_dfies WHERE keyflag <> abap_true.
    MOVE ls_dfies-offset TO ld_keylen.
    EXIT.
  ENDLOOP.

  "Insert the actual DFIES information with timestamp = 'actual'
  LOOP AT lt_dfies INTO ls_dfies.
    ls_tabdetails-crtimestmp = id_crtimestmp.
    MOVE-CORRESPONDING ls_dfies TO ls_tabdetails.
    ls_tabdetails-tabkeylen = ld_keylen.
    READ TABLE ct_tab_detail WITH KEY
                 tabname    = ls_dfies-tabname
                 fieldname  = ls_dfies-fieldname
                 crtimestmp = ls_tabdetails-crtimestmp
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      APPEND ls_tabdetails TO ct_tab_detail.
    ENDIF.
  ENDLOOP.

  "Append special_tabkey
  IF ld_special_tabkey EQ abap_true.
    ls_special_tabkey-crtimestmp = id_crtimestmp.
    ls_special_tabkey-tabname    = ls_tabdetails-tabname.
    READ TABLE ct_spec_tabkey WITH TABLE KEY
      tabname = ls_special_tabkey-tabname
      crtimestmp = ls_special_tabkey-crtimestmp
      TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      INSERT ls_special_tabkey INTO TABLE ct_spec_tabkey.
    ENDIF.
  ENDIF.
  CLEAR ls_tabdetails.

ENDFORM.                    "dfies_get
*&---------------------------------------------------------------------*
*&      Form  CRTIMESTMP_GET
*&---------------------------------------------------------------------*
*       get timestmp for log entry
*----------------------------------------------------------------------*
FORM crtimestmp_get USING id_logdate    TYPE sydats
                          id_logtime    TYPE sytime
                          id_tabname    TYPE tabname
                          it_tab_detail TYPE tt_tabdetails
                 CHANGING cd_crtimestmp TYPE crstamp.

  DATA: ld_crtstmp TYPE crstamp,
        lt_tab_det TYPE tt_tabdetails.

  FIELD-SYMBOLS: <ls_tabdetails> TYPE ts_tabdetails.

  lt_tab_det = it_tab_detail.
  SORT lt_tab_det BY tabname crtimestmp fieldname.

  CLEAR cd_crtimestmp.
  "Set the timestamp used by nametab-history:
  "Concatenate date and time
  CONCATENATE id_logdate id_logtime INTO ld_crtstmp.

  LOOP AT lt_tab_det ASSIGNING <ls_tabdetails>
    WHERE
      tabname    =  id_tabname AND
      crtimestmp LE ld_crtstmp.
    IF <ls_tabdetails>-crtimestmp > cd_crtimestmp.
      MOVE <ls_tabdetails>-crtimestmp TO cd_crtimestmp.
    ENDIF.
  ENDLOOP.

  IF cd_crtimestmp IS INITIAL.
    cd_crtimestmp = gc_crstamp_infinit.
  ENDIF.

ENDFORM.                    "crtimestmp_get
*&---------------------------------------------------------------------*
*&      Form  CONVERSION_INIT
*&---------------------------------------------------------------------*
*   Initialization of the conversion routine with the raw data
*   Consider table PRV_LOG_CP
*   In unicode systems (two byte) only codepage 4103 (LE) or
*   4102 (BE) are possible. Table logging always changes the endian
*   format to BE.
*   In unicode systems table logging changes all types.
*   In non-unicode systems only the number-types (s,I,F) are
*   changed by table logging.
*   Parameter endian in CL_ABAP_CONV_IN_CE is set for s,I,F (see
*   documentation of method "CREATE").
*   Because table logging also changes the endian format of CHARs
*   in unicode systems, codepage 4102 must be used
*----------------------------------------------------------------------*
FORM conversion_init USING id_logdate   TYPE sydats
                           id_logtime   TYPE sytime
                           id_logdata   TYPE dbtablog-logdata
                           id_versno    TYPE dbtablog-versno
                           it_codepages TYPE tt_codepages
                           id_codepage  TYPE abap_encod
                  CHANGING cr_converter TYPE REF TO cl_abap_conv_in_ce.

  DATA: ls_codepages TYPE prv_log_cp,
        ld_codepage  TYPE abap_encod.

  "Get corrected codepage  / sorted before
  LOOP AT it_codepages INTO ls_codepages
   WHERE  migdate > id_logdate OR
        ( migdate = id_logdate AND
          migtime > id_logtime ).
    EXIT.
  ENDLOOP.
  IF sy-subrc = 0.
    ld_codepage = ls_codepages-codepage.
  ELSE.
    ld_codepage = id_codepage.
  ENDIF.
  TRY.
      IF cr_converter IS BOUND.
        IF id_versno = '' AND sy-subrc NE 0.
          "Special handling for old records pre Unicode
          cr_converter->reset(
               encoding    = 'NON-UNICODE'
               endian      = 'B'
               ignore_cerr = abap_false
               input       = id_logdata ).
        ELSEIF id_versno = '02'.
          cr_converter->reset(
               encoding    = '4102'
               endian      = 'B'
               ignore_cerr = abap_false
               input       = id_logdata ).
        ELSE.
          cr_converter->reset(
               encoding    = ld_codepage
               endian      = 'B'
               ignore_cerr = abap_false
               input       = id_logdata ).
        ENDIF.
      ELSE.
        IF id_versno = '' AND sy-subrc NE 0.
          "Special handling for old records pre Unicode
          cr_converter = cl_abap_conv_in_ce=>create(
               encoding    = 'NON-UNICODE'
               endian      = 'B'
               ignore_cerr = abap_false
               input       = id_logdata ).
        ELSEIF id_versno = '02'.
          cr_converter = cl_abap_conv_in_ce=>create(
               encoding    = '4102'
               endian      = 'B'
               ignore_cerr = abap_false
               input       = id_logdata ).
        ELSE.
          cr_converter = cl_abap_conv_in_ce=>create(
               encoding    = ld_codepage
               endian      = 'B'
               ignore_cerr = abap_false
               input       = id_logdata ).
        ENDIF.
      ENDIF.
    CATCH cx_sy_codepage_converter_init.
      FREE cr_converter.
    CATCH cx_sy_conversion_codepage.
      FREE cr_converter.
    CATCH cx_parameter_invalid.
      FREE cr_converter.
  ENDTRY.

ENDFORM.                    "conversion_init
*&---------------------------------------------------------------------*
*&      Form  CODEPAGE_INIT
*&---------------------------------------------------------------------*
*       initialize the codepage settings
*----------------------------------------------------------------------*
FORM codepage_init CHANGING ct_codepages TYPE tt_codepages
                            cd_char_size TYPE i
                            cd_codepage  TYPE abap_encod.

  DATA: ld_code_page TYPE tcp00-cpcodepage.

  CLEAR: ct_codepages,
         cd_codepage,
         cd_char_size.

  "Determine if this is a two byte system.
  cd_char_size = cl_abap_char_utilities=>charsize.

  CALL FUNCTION 'SCP_GET_CODEPAGE_NUMBER'
    IMPORTING
      appl_codepage  = ld_code_page
    EXCEPTIONS
      internal_error = 1
      OTHERS         = 2.
  IF sy-subrc = 0.
    MOVE ld_code_page TO cd_codepage.
  ENDIF.

  "Get migration code_pages
  SELECT * FROM prv_log_cp INTO TABLE ct_codepages.
  IF sy-subrc = 0.
    SORT ct_codepages BY migdate migtime.
  ENDIF.

ENDFORM.                    "codepage_init
*&---------------------------------------------------------------------*
*&      Form  FIELD_CONVERT
*&---------------------------------------------------------------------*
*       convert a single field from LOGDATA into structure field
*----------------------------------------------------------------------*
FORM field_convert USING is_dbtablog   TYPE dbtablog
                         is_tab_detail TYPE ts_tabdetails
                         ir_converter  TYPE REF TO cl_abap_conv_in_ce
                         id_char_size  TYPE i
                CHANGING cd_field      TYPE any.

  DATA: lr_data_ref   TYPE REF TO data,
        lr_original_x TYPE REF TO data,
        ld_value(60)  TYPE c,
        ld_offset     TYPE doffset,
        ld_len        TYPE i,
        ld_logs       TYPE xstring.

  FIELD-SYMBOLS: <ld_logdata>    TYPE any,
                 <ld_original_x> TYPE any.

  "Unicode DBTABLOG includes no non-character-fields in key
  IF ( is_tab_detail-keyflag NE abap_true ) OR
     ( is_dbtablog-versno >= '01' ).
    PERFORM convert USING is_tab_detail
                          is_dbtablog-versno
                          ir_converter
                 CHANGING lr_data_ref
                          sy-subrc.
    CHECK sy-subrc = 0.
    ASSIGN lr_data_ref->* TO <ld_logdata>.
  ELSE.
    ld_offset = is_tab_detail-offset.
    ld_len    = is_tab_detail-intlen.
    "For types INT2, INT4, and FLTP no assign is possible
    "(!!!ASSIGN_BASE_WRONG_ALIGNMENT!!!)
    IF is_tab_detail-inttype   = 'b'
      OR is_tab_detail-inttype = 's'
      OR is_tab_detail-inttype = 'I'
      OR is_tab_detail-inttype = 'F'.
      PERFORM convert_key USING id_char_size
                                is_tab_detail
                                is_dbtablog
                       CHANGING ld_value
                                sy-subrc.
      CHECK sy-subrc = 0.
      ASSIGN ld_value TO <ld_logdata>.
    ELSE.
      TRY.
          IF is_tab_detail-inttype = 'P'.
            IF id_char_size GE 2.
              "Byte order must be ajusted
              CREATE DATA lr_original_x TYPE x
                LENGTH is_tab_detail-intlen.
              ASSIGN lr_original_x->* TO <ld_original_x>.
              ld_logs = is_dbtablog-logkey+ld_offset(ld_len).
              PERFORM byte_order_reconstruct CHANGING ld_logs
                                                      sy-subrc.
              CHECK sy-subrc = 0.
              <ld_original_x> = ld_logs.
              ASSIGN <ld_original_x> TO <ld_logdata>
                   CASTING TYPE p DECIMALS is_tab_detail-decimals.
            ELSE.
              ASSIGN is_dbtablog-logkey+ld_offset(ld_len)
                  TO <ld_logdata>
                  CASTING TYPE p DECIMALS is_tab_detail-decimals.
            ENDIF.
          ELSE.
            ASSIGN is_dbtablog-logkey+ld_offset(ld_len)
              TO <ld_logdata>
              CASTING TYPE (is_tab_detail-inttype).
          ENDIF.
        CATCH cx_sy_assign_cast_illegal_cast
              cx_sy_assign_cast_unknown_type.
          sy-subrc = 8.
      ENDTRY.
    ENDIF.
  ENDIF.
  CHECK sy-subrc = 0.
  cd_field = <ld_logdata>.

ENDFORM.                    "field_convert
*&---------------------------------------------------------------------*
*&      Form  CONVERT
*&---------------------------------------------------------------------*
*       convert a simple field of LOGDATA
*----------------------------------------------------------------------*
FORM convert USING is_tab_detail TYPE ts_tabdetails
                   id_versno     TYPE dbtablog-versno
                   ir_converter  TYPE REF TO cl_abap_conv_in_ce
          CHANGING cr_ref_data   TYPE REF TO data
                   cd_subrc      TYPE sy-subrc.

  DATA: ld_add           TYPE i,
        ld_intlen        TYPE i,
        ld_offset        TYPE doffset,
        ld_string_length TYPE sap_int4,
        ld_string_offset TYPE sap_int4,
        ld_xstring       TYPE xstring.

  FIELD-SYMBOLS: <ld_logdata> TYPE any.

  CLEAR cd_subrc.
  IF ir_converter IS INITIAL.
    cd_subrc = 12.
    RETURN.
  ENDIF.

* Create a local field with init type
  TRY.
      CASE is_tab_detail-inttype.
          "Integer types
        WHEN 'b'.
          CREATE DATA cr_ref_data TYPE int1.
        WHEN 's'.
          CREATE DATA cr_ref_data TYPE int2.
          "String types
        WHEN 'g'.
          CREATE DATA cr_ref_data TYPE string.
        WHEN 'y'.
          CREATE DATA cr_ref_data TYPE xstring.
          "Type P needs length + decimals
        WHEN 'P'.
          CREATE DATA cr_ref_data TYPE p
            LENGTH is_tab_detail-intlen
            DECIMALS is_tab_detail-decimals.
        WHEN OTHERS.
          "Only for Types C, N, X, P is length possible
          IF is_tab_detail-inttype CA 'CNX'.
            MOVE is_tab_detail-intlen TO ld_intlen.
            "Create 16-BIT-Units
            IF id_versno >= '02'     AND
               is_tab_detail-inttype CA 'CN'.
              ld_intlen = ld_intlen DIV id_versno.
            ENDIF.
            CREATE DATA cr_ref_data TYPE (is_tab_detail-inttype)
              LENGTH ld_intlen.
          ELSE.
            "All other types
            CREATE DATA cr_ref_data TYPE (is_tab_detail-inttype).
          ENDIF.
      ENDCASE.
    CATCH cx_sy_create_data_error.
*     error with CREATE DATA
      cd_subrc = 8.
      RETURN.
  ENDTRY.

* Read data with convert from conv
  ASSIGN cr_ref_data->* TO <ld_logdata>.
  IF id_versno >= '01'.
    ld_offset = is_tab_detail-offset.
  ELSE.
    ld_offset = is_tab_detail-offset - is_tab_detail-tabkeylen.
  ENDIF.

  IF ld_offset LT ir_converter->position.
*   Reset read position
    ld_xstring = ir_converter->get_buffer( ).
    ir_converter->reset(
      EXPORTING
        input = ld_xstring ).
  ENDIF.

  TRY.
*     In case alignment is needed for non char types
      IF ld_offset NE ir_converter->position.
        ld_add = ld_offset - ir_converter->position.
        ir_converter->skip_x( EXPORTING n = ld_add ).
      ENDIF.
      "Special handling for strings, read with length
      IF is_tab_detail-inttype CA 'gy'.
        "Read string pointer
        ir_converter->read( IMPORTING data = ld_string_offset ).
        ir_converter->read( IMPORTING data = ld_string_length ).
        "Skip to correct position
        ld_add = ld_string_offset - ir_converter->position.
        ir_converter->skip_x( EXPORTING n = ld_add ).
        IF id_versno >= '02'.
          ld_add = ld_string_length DIV id_versno.
        ELSE.
          ld_add = ld_string_length.
        ENDIF.
        ir_converter->read( EXPORTING n    = ld_add
                            IMPORTING data = <ld_logdata> ).
        "Reset read position
        ld_xstring = ir_converter->get_buffer( ).
        ir_converter->reset( EXPORTING input = ld_xstring ).
      ELSE.
        ir_converter->read( IMPORTING data = <ld_logdata> ).
      ENDIF.
    CATCH cx_parameter_invalid.
      "Field conversion not possible
      cd_subrc = 4.
  ENDTRY.

ENDFORM.                    "convert
*&---------------------------------------------------------------------*
*&      Form  CONVERT_KEY
*&---------------------------------------------------------------------*
*       get key entry for initial DBLOGTAB-VERSNO
*----------------------------------------------------------------------*
FORM convert_key USING id_char_size  TYPE i
                       is_tab_detail TYPE ts_tabdetails
                       is_dbtablog   TYPE dbtablog
              CHANGING cd_value      TYPE clike
                       cd_subrc      TYPE sy-subrc.

  DATA: ld_bytes TYPE xstring,
        ld_logs  TYPE xstring,
        ld_offs  TYPE i,
        ld_len   TYPE i.

  FIELD-SYMBOLS: <ld_xlogs> TYPE any.

  ld_offs = is_tab_detail-offset.
  ld_len  = is_tab_detail-intlen.
  ld_logs = is_dbtablog-logkey+ld_offs(ld_len).

  CLEAR cd_subrc.

  IF id_char_size GE 2.
    "In case this is a two byte system: Byte order of the logs that derive
    "from non-unicode must be reconstructed
    PERFORM byte_order_reconstruct CHANGING ld_logs
                                            cd_subrc.
  ENDIF.
  CHECK cd_subrc = 0.
  PERFORM convert_type_to_char USING is_tab_detail-inttype
                                     ld_logs
                            CHANGING cd_value
                                     cd_subrc.

ENDFORM.                    "convert_key
*&---------------------------------------------------------------------*
*&      Form  BYTE_ORDER_RECONSTRUCT
*&---------------------------------------------------------------------*
*    All non-char-like table log fields that are created in a pre
*    unicode environment got wrong byte-order if current system is
*    a 2-byte system -> reconstruct 1-byte-system byte order
*----------------------------------------------------------------------*
FORM byte_order_reconstruct CHANGING cd_logs  TYPE xstring
                                     cd_subrc TYPE sy-subrc.

  DATA: lr_conv  TYPE REF TO cl_abap_conv_out_ce.

  CLEAR cd_subrc.

  "Create instance for log
  TRY.
      lr_conv = cl_abap_conv_out_ce=>create(
          encoding = 'NON-UNICODE'
          endian   = 'B' ).
    CATCH cx_parameter_invalid_range.
      cd_subrc = 12.
      RETURN.
    CATCH cx_sy_codepage_converter_init .
      cd_subrc = 12.
      RETURN.
  ENDTRY.

  "Reset output buffer.
  lr_conv->reset( ).

  "Fill output buffer
  lr_conv->write( EXPORTING data = cd_logs ).

  cd_logs = lr_conv->get_buffer( ).

ENDFORM.                    "byte_order_reconstruct
*&---------------------------------------------------------------------*
*&      Form  CONVERT_TYPE_TO_CHAR
*&---------------------------------------------------------------------*
*       for special types a conversion to CHAR is needed
*----------------------------------------------------------------------*
FORM convert_type_to_char USING id_inttype TYPE inttype
                                id_logs    TYPE xstring
                       CHANGING cd_value   TYPE clike
                                cd_subrc   TYPE sy-subrc.

  DATA: ld_field_f  TYPE f,
        ld_field_i1 TYPE int1,
        ld_field_i2 TYPE int2,
        ld_field_i4 TYPE i.

  CONSTANTS: lc_float_type TYPE x031l-fieldtype VALUE '88',
             lc_int2_type  TYPE x031l-fieldtype VALUE 'A8'.

  FIELD-SYMBOLS: <ld_value> TYPE x.

  "Catch possible errors in conversion
  CATCH SYSTEM-EXCEPTIONS convt_no_number    = 2
                          convt_overflow     = 3.
    CASE id_inttype.
      WHEN 'I'.
        MOVE id_logs TO ld_field_i4.
        MOVE ld_field_i4 TO cd_value.
      WHEN 'F'.
        ASSIGN ld_field_f TO <ld_value> CASTING.
        MOVE id_logs TO <ld_value>.
        CALL FUNCTION 'DB_CONVERT_FIELD_TO_HOST'
          EXPORTING
            type        = lc_float_type
          CHANGING
            field       = <ld_value>
          EXCEPTIONS
            wrong_param = 0
            OTHERS      = 0.
        MOVE ld_field_f TO cd_value.
      WHEN 's'.
        ASSIGN ld_field_i2 TO <ld_value> CASTING.
        MOVE id_logs TO <ld_value>.
        CALL FUNCTION 'DB_CONVERT_FIELD_TO_HOST'
          EXPORTING
            type        = lc_int2_type
          CHANGING
            field       = <ld_value>
          EXCEPTIONS
            wrong_param = 0
            OTHERS      = 0.
        MOVE ld_field_i2 TO cd_value.
      WHEN 'b'.
        MOVE id_logs TO ld_field_i1.
        MOVE ld_field_i1 TO cd_value.
      WHEN OTHERS.
        cd_subrc = 1.
    ENDCASE.
  ENDCATCH.
  IF sy-subrc <> 0.
    CLEAR cd_value.
    cd_subrc = sy-subrc.
  ENDIF.

ENDFORM.                    "convert_type_to_char

*&      Form  F99_DDIF_FIELDINFO_GET
*&---------------------------------------------------------------------*
*       get field info
*----------------------------------------------------------------------*
*      -->P_TABNAME   table/structure name
*      <--P_FIELDTAB  field tab
*      <--P_SUBRC     return code
*----------------------------------------------------------------------*
FORM f99_ddif_fieldinfo_get
     TABLES   p_fieldtab       STRUCTURE dfies
     USING    VALUE(p_tabname) TYPE c
     CHANGING p_subrc          LIKE sy-subrc.

  DATA: tabname  LIKE dfies-tabname,
        wa_dfies LIKE dfies.


  tabname = p_tabname.
  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING
      tabname   = tabname "#EC DOM_EQUAL
    TABLES
      dfies_tab = p_fieldtab
    EXCEPTIONS
      OTHERS    = 5.
  IF sy-subrc <> 0.                    "try without texts
    CALL FUNCTION 'DDIF_NAMETAB_GET'
      EXPORTING
        tabname   = tabname "#EC DOM_EQUAL
      TABLES
        dfies_tab = p_fieldtab
      EXCEPTIONS
        OTHERS    = 5.
    p_subrc = sy-subrc.
  ELSE.
    p_subrc = sy-subrc.
*   check if all texts are available
    LOOP AT p_fieldtab WHERE langu IS INITIAL.
*     read text from corresponding source table field
      SELECT src_struct FROM txw_c_soex INTO tabname    "#EC CI_NOFIRST
             WHERE exp_struct = p_tabname.
        CALL FUNCTION 'DDIF_FIELDINFO_GET'
          EXPORTING
            tabname    = tabname "#EC DOM_EQUAL
*           LANGU      = SY-LANGU
            lfieldname = p_fieldtab-lfieldname
          IMPORTING
            dfies_wa   = wa_dfies
          EXCEPTIONS
            OTHERS     = 3.
        IF sy-subrc = 0.
          p_fieldtab-fieldtext = wa_dfies-fieldtext.
          p_fieldtab-reptext = wa_dfies-reptext.
          p_fieldtab-scrtext_s = wa_dfies-scrtext_s.
          p_fieldtab-scrtext_m = wa_dfies-scrtext_m.
          p_fieldtab-scrtext_l = wa_dfies-scrtext_l.
          MODIFY p_fieldtab.
          EXIT.
        ENDIF.
      ENDSELECT.
    ENDLOOP.
  ENDIF.

ENDFORM.                               " F99_DDIF_FIELDINFO_GET

*---------------------------------------------------------------------*
*       FORM WRITE_CURRENCY                                           *
*---------------------------------------------------------------------*
*       convert currency amount to string                             *
*       - use decimal point                                           *
*       - remove separator characters                                 *
*---------------------------------------------------------------------*
*  -->  P_AMOUNT                                                      *
*  -->  P_CURRENCY_UNIT                                               *
*  -->  P_STRING                                                      *
*---------------------------------------------------------------------*
FORM write_currency
     USING p_amount        TYPE p
           p_currency_unit LIKE tcurc-waers
           p_string        TYPE c.

  DATA: dec2point(2) TYPE c VALUE ',.'.


* convert separator to decimal point
  WRITE p_amount TO p_string CURRENCY p_currency_unit
        NO-GROUPING
        NO-SIGN
        LEFT-JUSTIFIED.
  TRANSLATE p_string USING dec2point.

* put minus sign before number
  IF p_amount < 0.
    SHIFT p_string RIGHT.
    p_string(1) = '-'.
  ENDIF.

ENDFORM.


*---------------------------------------------------------------------*
*       FORM WRITE_QUANTITY                                           *
*---------------------------------------------------------------------*
*       convert quantity amount to string                             *
*       - use decimal point                                           *
*       - remove separator characters                                 *
*---------------------------------------------------------------------*
*  -->  P_AMOUNT                                                      *
*  -->  P_QUANTITY_UNIT                                               *
*  -->  P_STRING                                                      *
*---------------------------------------------------------------------*
FORM write_quantity
     USING p_amount        TYPE p
           p_quantity_unit LIKE t006-msehi
           p_string        TYPE c.

  DATA: dec2point(2) TYPE c VALUE ',.'.


* convert separator to decimal point
  WRITE p_amount TO p_string UNIT p_quantity_unit
        NO-GROUPING
        NO-SIGN
        LEFT-JUSTIFIED.
  TRANSLATE p_string USING dec2point.

* put minus sign before number
  IF p_amount < 0.
    SHIFT p_string RIGHT.
    p_string(1) = '-'.
  ENDIF.

ENDFORM.


*---------------------------------------------------------------------*
*       FORM WRITE_DECIMAL_VALUE                                      *
*---------------------------------------------------------------------*
*       convert decimal value to string                               *
*       - use decimal point                                           *
*       - remove separator characters                                 *
*---------------------------------------------------------------------*
*  -->  P_AMOUNT                                                      *
*  -->  P_STRING                                                      *
*---------------------------------------------------------------------*
FORM write_decimal_value
     USING p_amount TYPE p
           p_string TYPE c.

  DATA: dec2point(2) TYPE c VALUE ',.'.


* write decimal value to string
  WRITE p_amount TO p_string
        USING NO EDIT MASK             "no conv. exits (e.g. BKPF-KURSF)
        NO-GROUPING                    "ignore 000 separators
        NO-SIGN                        "ignore sign
        LEFT-JUSTIFIED.

* convert decimal comma to decimal point
  TRANSLATE p_string USING dec2point.

* put minus sign before number
  IF p_amount < 0.
    SHIFT p_string RIGHT.
    p_string(1) = '-'.
  ENDIF.

ENDFORM.
*&---------------------------------------------------------------------*
*&      Form  PROCESS_CD_GENERIC
*&---------------------------------------------------------------------*
*       fill genric parts for DBTABLOG change entries
*----------------------------------------------------------------------*
FORM process_cd_generic USING is_dbtablog   TYPE dbtablog
                              ir_tab_old    TYPE REF TO data
                              ir_tab_new    TYPE REF TO data
                     CHANGING ct_cd_gen_all TYPE tt_cd_gen_all.

  STATICS: st_dfies TYPE TABLE OF dfies.

  DATA: ls_cd_gen      TYPE txw_cd_gen,
        ls_cd_dbtablog TYPE txw_cd_dbtablog,
        ls_cd_gen_all  TYPE ts_cd_gen_all,
        ld_subrc       TYPE sy-subrc,
        ld_key_len     TYPE i.                              "H2693594

  FIELD-SYMBOLS: <ls_strc_old>  TYPE any,
                 <ls_strc_new>  TYPE any,
                 <ls_dfies>     TYPE dfies,
                 <ld_field_old> TYPE any,
                 <ld_field_new> TYPE any.

  READ TABLE st_dfies ASSIGNING <ls_dfies> INDEX 1.
  IF sy-subrc <> 0 OR
     <ls_dfies>-tabname <> is_dbtablog-tabname.
    REFRESH st_dfies.
    PERFORM f99_ddif_fieldinfo_get TABLES st_dfies
                                    USING is_dbtablog-tabname
                                 CHANGING ld_subrc.
    IF ld_subrc <> 0.
      MESSAGE x016(xw).
    ENDIF.
  ENDIF.

  REFRESH ct_cd_gen_all.
  ASSIGN ir_tab_old->* TO <ls_strc_old>.

* generic fields of DBTABLOG
  MOVE-CORRESPONDING is_dbtablog TO ls_cd_dbtablog.

* generic fields for TXW_CD_GEN
  ls_cd_gen-username = is_dbtablog-username.
  ls_cd_gen-udate    = is_dbtablog-logdate.
  ls_cd_gen-utime    = is_dbtablog-logtime.
  ls_cd_gen-tcode    = is_dbtablog-tcode.
  ls_cd_gen-tabname  = is_dbtablog-tabname.
  ls_cd_gen-chngind  = is_dbtablog-optype.
  ls_cd_gen-langu    = is_dbtablog-language.
  ld_key_len = strlen( is_dbtablog-logkey ).                "H2693594
  IF ld_key_len LE 70.                                      "H2693594
    ls_cd_gen-tabkey = is_dbtablog-logkey.                  "H2693594
  ELSE.                                                     "H2693594
    CONCATENATE is_dbtablog-logkey(69) '*'                  "H2693594
           INTO ls_cd_gen-tabkey.                           "H2693594
  ENDIF.                                                    "H2693594

* handle different options
  IF is_dbtablog-optype = gc_optype-update.
    CHECK ir_tab_new IS BOUND.
    ASSIGN ir_tab_new->* TO <ls_strc_new>.
*   <ls_strc_old> contain values before update and
*   <ls_strc_new> contain values after the update
*   do a comparison for each single field and add an entry
*   for each changed field to extract
    CHECK <ls_strc_old> <> <ls_strc_new>.
    LOOP AT st_dfies ASSIGNING <ls_dfies>.
      UNASSIGN: <ld_field_old>,
                <ld_field_new>.
      ASSIGN COMPONENT <ls_dfies>-fieldname
             OF STRUCTURE <ls_strc_old> TO <ld_field_old>.
      ASSIGN COMPONENT <ls_dfies>-fieldname
             OF STRUCTURE <ls_strc_new> TO <ld_field_new>.
      IF <ld_field_old> IS ASSIGNED AND
         <ld_field_new> IS ASSIGNED AND
         <ld_field_old> <> <ld_field_new>.
        ls_cd_gen-fname = <ls_dfies>-fieldname.
        ls_cd_gen-ftext = <ls_dfies>-fieldtext.
        ls_cd_gen-outlen = <ls_dfies>-outputlen.
        CASE <ls_dfies>-inttype.
          WHEN 'P'.
            PERFORM write_decimal_value
                           USING <ld_field_old>
                                 ls_cd_gen-value_old.
            PERFORM write_decimal_value
                           USING <ld_field_new>
                                 ls_cd_gen-value_new.
          WHEN 'F'.
            ls_cd_gen-value_old = <ld_field_old>.
            ls_cd_gen-value_new = <ld_field_new>.
            CONDENSE ls_cd_gen-value_old.
            CONDENSE ls_cd_gen-value_new.
          WHEN OTHERS.
            ls_cd_gen-value_old = <ld_field_old>.
            ls_cd_gen-value_new = <ld_field_new>.
        ENDCASE.
        MOVE-CORRESPONDING ls_cd_dbtablog TO ls_cd_gen_all.
        MOVE-CORRESPONDING ls_cd_gen      TO ls_cd_gen_all.
        IF p_real EQ abap_true.
          CHECK ls_cd_gen_all-value_old NE ls_cd_gen_all-value_new.
        ENDIF.
        APPEND ls_cd_gen_all TO ct_cd_gen_all.
      ENDIF.
    ENDLOOP.
  ELSE.
*   only key informations are needed
    MOVE-CORRESPONDING ls_cd_dbtablog TO ls_cd_gen_all.
    MOVE-CORRESPONDING ls_cd_gen      TO ls_cd_gen_all.

    IF p_real EQ abap_true.
      CHECK ls_cd_gen_all-value_old NE ls_cd_gen_all-value_new.
    ENDIF.

    APPEND ls_cd_gen_all TO ct_cd_gen_all.
  ENDIF.

ENDFORM.                    " process_cd_generic



FORM condense_t_dates CHANGING p_date_range LIKE t_dates.

  DATA: l_count TYPE i.

  l_count = 1.
  LOOP AT t_dates.
    IF l_count = 1.
      p_date_range-dat_from = t_dates-dat_from.
      p_date_range-dat_to = t_dates-dat_to.
    ELSE.
      IF t_dates-dat_from < p_date_range-dat_from.
        p_date_range-dat_from = t_dates-dat_from.
      ENDIF.
      IF t_dates-dat_to > p_date_range-dat_to.
        p_date_range-dat_to = t_dates-dat_to.
      ENDIF.
    ENDIF.
    l_count = l_count + 1.
  ENDLOOP.

ENDFORM.                    "condense_t_dates



*&---------------------------------------------------------------------*
*&      Form  PROCESS_CD_USR05_DETAIL    "new with note 2246560
*&---------------------------------------------------------------------*
*       create TXW_CD_USR05 entry and add to extract
*----------------------------------------------------------------------*
FORM process_cd_usr05_detail USING is_dblog TYPE dbtablog
                                  ir_usr051 TYPE REF TO data
                                  ir_usr052 TYPE REF TO data.

  DATA: ls_cd_usr05   TYPE txw_cd_usr05,
        lt_cd_gen_all TYPE tt_cd_gen_all,
        ls_cd_gen     TYPE txw_cd_gen.

  FIELD-SYMBOLS: <ls_usr05_old>  TYPE usr05,
                 <ls_cd_gen_all> TYPE ts_cd_gen_all.

  CHECK ir_usr051 IS BOUND.
* get all changed fields for log entry
  PERFORM process_cd_generic USING is_dblog
                                   ir_usr051
                                   ir_usr052
                          CHANGING lt_cd_gen_all.

  ASSIGN ir_usr051->* TO <ls_usr05_old> CASTING.

* export the data to extract
  LOOP AT lt_cd_gen_all ASSIGNING <ls_cd_gen_all>.
*   generic fields
    MOVE-CORRESPONDING <ls_cd_gen_all> TO ls_cd_usr05.
*   key fields for USR05
    ls_cd_usr05-bname = <ls_usr05_old>-bname.
*   export to file
    APPEND ls_cd_usr05 TO lt_output.
*    CALL FUNCTION 'TXW_SEGMENT_RECORD_EXPORT'
*      EXPORTING
*        data_record = ls_cd_usr05.
  ENDLOOP.

ENDFORM.                    "process_cd_USR05_detail
*&---------------------------------------------------------------------*
*&      Form  PROCESS_CD_USR05_NEXT      "new with note 2246560
*&---------------------------------------------------------------------*
*       get new USR05 data to compare the fields
*----------------------------------------------------------------------*
FORM process_cd_usr05_next USING is_dbtablog   TYPE dbtablog
                                id_tabix_next TYPE i
                                id_bname      TYPE usr05-bname
                                it_dbtablog   TYPE tt_dbtablog
                       CHANGING cr_tab_new    TYPE REF TO data.

  DATA: ls_dbtablog_new TYPE dbtablog,
        ld_next         TYPE flag.                         "note 2419646

  FIELD-SYMBOLS: <ls_usr05_new> TYPE usr05.

* 1. try next entry in selected DBLOGTAB
  READ TABLE it_dbtablog INTO ls_dbtablog_new
                         INDEX id_tabix_next.
  IF sy-subrc <> 0 OR
     ls_dbtablog_new-logkey <> is_dbtablog-logkey.
*   2. try to select from DBTABLOG
    SELECT * FROM dbtablog INTO ls_dbtablog_new            "note 2419646
                           WHERE tabname = is_dbtablog-tabname
                             AND logdate >=                "note 2419646
                                      is_dbtablog-logdate  "note 2419646
                             AND logkey  = is_dbtablog-logkey
                    ORDER BY logdate logtime.
      IF ls_dbtablog_new-logdate > is_dbtablog-logdate.    "note 2419646
*       avoid full table scan in case of no NEXT entry     "note 2419646
        ld_next = 'X'.                                     "note 2419646
        EXIT.                                              "note 2419646
      ENDIF.                                               "note 2419646
    ENDSELECT.
    IF ld_next IS INITIAL.                                 "note 2419646
*     3. use actual DB tab entry
      IF NOT cr_tab_new IS BOUND.
        CREATE DATA cr_tab_new TYPE (is_dbtablog-tabname).
      ENDIF.
      ASSIGN cr_tab_new->* TO <ls_usr05_new> CASTING.
      SELECT SINGLE * FROM usr05 INTO <ls_usr05_new>
                   WHERE bname = id_bname.
      IF sy-subrc <> 0.
*       no comparison available
        RETURN.
      ENDIF.
    ENDIF.
  ENDIF.
  IF NOT <ls_usr05_new> IS ASSIGNED.
    PERFORM dbtablog_convert USING ls_dbtablog_new
                                   is_dbtablog-tabname
                          CHANGING cr_tab_new.
  ENDIF.

ENDFORM.                    "process_cd_USR05_next
