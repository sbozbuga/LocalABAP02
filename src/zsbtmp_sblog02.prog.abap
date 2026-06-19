*----------------------------------------------------------------------*
* Report  ZSBTMP_SBLOG
*
*----------------------------------------------------------------------*
* Transaktion                                                          *
* Datum                                                                *
*----------------------------------------------------------------------*
* Firma               CTDI GmbH Malsch Headquarter                     *
*                                                                      *
* Beschreibung:  1.)                                                   *
*                2.)                                                   *
*                3.)                                                   *
*                                                                      *
*                                                                      *
*----------------------------------------------------------------------*
* Anforderer:                                                          *
* Ticket....:                                                          *
* Konzept...:  ???                                                     *
* Betreuung.:                                                          *
*----------------------------------------------------------------------*
* Entwickler...:                                                       *
*                                                                      *
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
* xx.xx.xxxx ???         ???
*----------------------------------------------------------------------*
REPORT zsbtmp_sblog02.

TABLES: usr05, dbtablog.

DATA: gr_convert      TYPE REF TO cl_abap_conv_out_ce,      "H1680476
      gd_unicode_mode TYPE txw_unicode_mode.                "H1680476
CONSTANTS: gc_umode_utf8  TYPE txw_unicode_mode VALUE '3',  "H1680476
           gc_utf8_encode TYPE abap_encod VALUE '4110'.     "H1680476

*----------------------------------------------------------------------*
*   generic handling for DBTABLOG change documents  "new with 2246560
*----------------------------------------------------------------------*
TYPES: BEGIN OF ts_tabdetails,
         tabname    TYPE cdpos-tabname,
         crtimestmp TYPE crstamp,
         fieldname  TYPE cdpos-fname,
         tabtext    TYPE dd02t-ddtext,
         tabkeylen  TYPE i,
         rollname   TYPE rollname,
         keyflag    TYPE keyflag,
         datatype   TYPE dfies-datatype,
         leng       TYPE ddleng,
         intlen     TYPE intlen,
         decimals   TYPE decimals,
         inttype    TYPE inttype,
         offset     TYPE doffset,
       END OF ts_tabdetails,
       BEGIN OF ts_special_tabkey,
         tabname    TYPE dbtablog-tabname,
         crtimestmp TYPE crstamp,
       END OF ts_special_tabkey,
       tt_tabdetails     TYPE STANDARD TABLE OF ts_tabdetails,
       tt_special_tabkey TYPE SORTED TABLE OF ts_special_tabkey
                         WITH UNIQUE KEY tabname crtimestmp,
       tt_dbtablog       TYPE STANDARD TABLE OF dbtablog,
       tt_codepages      TYPE TABLE OF prv_log_cp,
       BEGIN OF ts_cd_gen_all.
         INCLUDE STRUCTURE txw_cd_dbtablog.
         INCLUDE STRUCTURE txw_cd_gen.
       TYPES: END OF ts_cd_gen_all,
       tt_cd_gen_all TYPE TABLE OF ts_cd_gen_all,
       BEGIN OF txw_cd_usr05,
         bname TYPE usr05-bname.
         INCLUDE STRUCTURE txw_cd_dbtablog.
         INCLUDE STRUCTURE txw_cd_gen.
       TYPES: END OF txw_cd_usr05.

CONSTANTS: gc_crstamp_infinit TYPE crstamp VALUE '99999999999999',
           BEGIN OF gc_optype,
             insert TYPE dbtablog-optype VALUE 'I',
             delete TYPE dbtablog-optype VALUE 'D',
             update TYPE dbtablog-optype VALUE 'U',
           END OF gc_optype.

DATA: t_dates TYPE TABLE OF txw_dates WITH HEADER LINE.     "H2301883

*---------------------------------------------------------------------*
* TYPES
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_output,
         bname     TYPE usr05-bname,
         parid     TYPE usr05-parid,
         old_value TYPE usr05-parva,
         new_value TYPE usr05-parva,
         uname     TYPE syuname,
         udate     TYPE sydatum,
         utime     TYPE syuzeit,
         tcode     TYPE sy-tcode,
         icon      TYPE icon_d,       " ✅ Icon column
         color     TYPE lvc_t_scol,   " ✅ Color column
       END OF ty_output.

DATA: lt_output TYPE TABLE OF txw_cd_usr05,
      ls_output TYPE txw_cd_usr05.

*---------------------------------------------------------------------*
* SELECTION SCREEN
*---------------------------------------------------------------------*
*%%%%%%%%%%%%%%%%%%%%%%%%%% Selektionsbild %%%%%%%%%%%%%%%%%%%%%%%%%%%%*
SELECTION-SCREEN : BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-b01.
SELECT-OPTIONS   :   s_bname        FOR usr05-bname.
SELECTION-SCREEN : END   OF BLOCK b01.

"---Auswertezeitraum
SELECTION-SCREEN BEGIN OF BLOCK interv WITH FRAME TITLE TEXT-001.
*SELECTION-SCREEN BEGIN OF LINE.
*SELECTION-SCREEN COMMENT 1(24) FOR FIELD dbeg.        "UFi2337770/2004b
PARAMETERS: dbeg TYPE tlog_begdat.                          "1. Tag.
*SELECTION-SCREEN COMMENT 40(24) FOR FIELD tbeg.
*PARAMETERS: tbeg TYPE tlog_begtime.      "UFi2337770/2004e"Anfangszeit
*SELECTION-SCREEN END OF LINE.
*SELECTION-SCREEN BEGIN OF LINE.
*SELECTION-SCREEN COMMENT 1(24) FOR FIELD dend.        "UFi2337770/2004b
PARAMETERS: dend TYPE tlog_enddat DEFAULT sy-datum.         "letzer Tag
*SELECTION-SCREEN COMMENT 40(24) FOR FIELD tend.
*PARAMETERS: tend TYPE tlog_endtime DEFAULT sy-uzeit.
**                                          "UFi2337770/2004e"Schlußzeit
*SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN END OF BLOCK interv.

SELECTION-SCREEN : BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-b02.
SELECT-OPTIONS   :   s_usera        FOR dbtablog-username,
                     s_tcode        FOR dbtablog-tcode.
SELECT-OPTIONS s_optype FOR dbtablog-optype DEFAULT 'U'.
PARAMETERS p_real AS CHECKBOX DEFAULT abap_true.
SELECTION-SCREEN : END   OF BLOCK b02.

*---------------------------------------------------------------------*
* START-OF-SELECTION
*---------------------------------------------------------------------*
START-OF-SELECTION.

  PERFORM get_data.
  PERFORM display_alv.

*---------------------------------------------------------------------*
* GET DATA
*---------------------------------------------------------------------*
FORM get_data.

  DATA: ld_subrc  TYPE sy-subrc,
        ls_dates  LIKE t_dates,
        ld_key    TYPE logkey,
        lt_dblog  TYPE TABLE OF dbtablog,
        ld_tabix  TYPE sy-tabix,
        lr_usr051 TYPE REF TO data,
        lr_usr052 TYPE REF TO data.

  FIELD-SYMBOLS: <ls_dblog> TYPE dbtablog,
                 <ls_usr05> TYPE usr05.


** get range of dates
*  PERFORM condense_t_dates CHANGING ls_dates.


* get change documents for USR05 (acutal client only)
* FM DBLOG_READ use a sorted result table with wrong
* sorting order - do the select directly
  CONCATENATE sy-mandt s_bname-low '%' INTO ld_key.
  SELECT * FROM dbtablog INTO TABLE lt_dblog
           WHERE tabname = 'USR05'
             AND logdate BETWEEN dbeg
                             AND dend
             AND logkey  LIKE ld_key
           ORDER BY logkey logdate logtime.

  LOOP AT lt_dblog ASSIGNING <ls_dblog>.
*   save TABIX for comparing entry
    ld_tabix = sy-tabix + 1.
    CASE <ls_dblog>-optype.
      WHEN gc_optype-insert OR
           gc_optype-delete.
*       insert/delete - only conversion
        PERFORM dbtablog_convert USING <ls_dblog>
                                       'USR05'
                              CHANGING lr_usr051.
      WHEN gc_optype-update.
*       update - conversion & comparison row needed
        PERFORM dbtablog_convert USING <ls_dblog>
                                       'USR05'
                              CHANGING lr_usr051.
        ASSIGN lr_usr051->* TO <ls_usr05> CASTING.
        PERFORM process_cd_usr05_next USING <ls_dblog>
                                           ld_tabix
                                           <ls_usr05>-bname
                                           lt_dblog
                                  CHANGING lr_usr052.
      WHEN OTHERS.
        CONTINUE.                   "not supported
    ENDCASE.
*   now process the change log entry
    PERFORM process_cd_usr05_detail USING <ls_dblog>
                                         lr_usr051
                                         lr_usr052.
  ENDLOOP.


*  DATA: lt_log   TYPE TABLE OF dbtablog,
*        lt_dblog TYPE TABLE OF dblog,
*        ls_dblog TYPE dblog.
*
*  " Read DBTABLOG
*  SELECT *
*    INTO TABLE lt_log
*    FROM dbtablog
*    WHERE tabname = 'USR05'
*      AND objectid IN @s_bname.
*
*  " Decode logs (OLD / NEW)
*  CALL FUNCTION 'DBLOG_READ'
*    TABLES
*      logtab = lt_log
*      dblog  = lt_dblog.
*
*  LOOP AT lt_dblog INTO ls_dblog WHERE tabname = 'USR05'.
*
*    CLEAR ls_output.
*
*    " Technical fields
*    ls_output-uname = ls_dblog-username.
*    ls_output-udate = ls_dblog-udate.
*    ls_output-utime = ls_dblog-utime.
*    ls_output-tcode = ls_dblog-tcode.
*
*    " Split OBJECTID -> BNAME + PARID
*    DATA(lv_key) = ls_dblog-objectid.
*
*    ls_output-bname = lv_key+0(12).
*    ls_output-parid = lv_key+12(20).
*
*    " OLD / NEW values
*    CASE ls_dblog-chngind.
*      WHEN 'U'.   " Update
*        ls_output-old_value = ls_dblog-old_value.
*        ls_output-new_value = ls_dblog-new_value.
*        ls_output-icon = icon_change.   " 🔄
*
*      WHEN 'I'.   " Insert
*        ls_output-new_value = ls_dblog-new_value.
*        ls_output-icon = icon_create.   " ➕
*
*      WHEN 'D'.   " Delete
*        ls_output-old_value = ls_dblog-old_value.
*        ls_output-icon = icon_delete.   " ❌
*    ENDCASE.
*
**---------------------------------------------------------------*
** COLOR LOGIC
**---------------------------------------------------------------*
*    DATA: ls_color TYPE lvc_s_scol.
*
*    CLEAR ls_output-color.
*
*    " UPDATE → highlight both fields in RED
*    IF ls_dblog-chngind = 'U'
*       AND ls_output-old_value <> ls_output-new_value.
*
*      ls_color-fname = 'OLD_VALUE'.
*      ls_color-color-col = 6. " red
*      ls_color-color-int = 1.
*      APPEND ls_color TO ls_output-color.
*
*      ls_color-fname = 'NEW_VALUE'.
*      APPEND ls_color TO ls_output-color.
*
*    ENDIF.
*
*    " INSERT → green new value
*    IF ls_dblog-chngind = 'I'.
*
*      ls_color-fname = 'NEW_VALUE'.
*      ls_color-color-col = 5. " green
*      ls_color-color-int = 1.
*      APPEND ls_color TO ls_output-color.
*
*    ENDIF.
*
*    " DELETE → yellow old value
*    IF ls_dblog-chngind = 'D'.
*
*      ls_color-fname = 'OLD_VALUE'.
*      ls_color-color-col = 3. " yellow
*      ls_color-color-int = 1.
*      APPEND ls_color TO ls_output-color.
*
*    ENDIF.
*
*    APPEND ls_output TO lt_output.
*
*  ENDLOOP.

ENDFORM.

*---------------------------------------------------------------------*
* DISPLAY ALV
*---------------------------------------------------------------------*
FORM display_alv.

  DATA: lo_alv  TYPE REF TO cl_salv_table,
        lo_cols TYPE REF TO cl_salv_columns_table,
        lo_col  TYPE REF TO cl_salv_column.

  cl_salv_table=>factory(
    IMPORTING r_salv_table = lo_alv
    CHANGING  t_table      = lt_output ).

  lo_cols = lo_alv->get_columns( ).

*  " Enable color handling
*  lo_cols->set_color_column( 'COLOR' ).

  " Optimize columns
  lo_cols->set_optimize( abap_true ).

*  " Set icon column properly
*  TRY.
*      lo_col ?= lo_cols->get_column( 'ICON' ).
**      lo_col->set_icon( abap_true ).
*      lo_col->set_medium_text( 'Change Type' ).
*    CATCH cx_salv_not_found.
*  ENDTRY.

  lo_alv->display( ).

ENDFORM.


*include LTXW0E1F90.
INCLUDE zsbtmp002_ltxw0e1f32.
*INCLUDE zsbtmp_ltxw0e1f32.
