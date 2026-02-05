CLASS zcl_mm_stock_on_date DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.


    TYPES: BEGIN OF lty_calc_key,
             werks TYPE werks_d,
             matnr TYPE matnr,
             lgort TYPE lgort_d,
             sobkz TYPE sobkz,
             ssnum TYPE char20,
           END OF lty_calc_key.

    TYPES: ranges_mtart_tt TYPE RANGE OF mtart.

    " 3. Anchor Decision (Per Segment)


    " 4. Movement Structure (Direct Select)
    TYPES: BEGIN OF lty_move,
             mblnr     TYPE mblnr,
             mjahr     TYPE mjahr,
             zeile     TYPE mblpo,
             budat     TYPE budat,
             shkzg     TYPE shkzg,
             matnr     TYPE matnr,
             werks     TYPE werks_d,
             lgort     TYPE lgort_d,
             sobkz     TYPE sobkz,
             lifnr     TYPE lifnr,
             mat_kdauf TYPE mat_kdauf, " Sales Order (Valuated Stock)
             mat_kdpos TYPE mat_kdpos, " Sales Order Item
             insmk     TYPE insmk,     " Stock Type: ''=labst, X/2=insme, S/3=speme
             menge     TYPE menge_d,
           END OF lty_move.

    " 5. Output Structures (Stock Results)
    " Detail: Per material/plant/storage location/special stock/date
    TYPES: BEGIN OF lty_stock_detail,
             matnr TYPE matnr,        " Material
             werks TYPE werks_d,      " Plant
             lgort TYPE lgort_d,      " Storage Location
             sobkz TYPE sobkz,        " Special Stock Indicator
             ssnum TYPE char20,       " Special Stock Number
             budat TYPE budat,        " Date
             labst TYPE labst,        " Unrestricted Stock
             insme TYPE insme,        " Quality Inspection Stock
             speme TYPE speme,        " Blocked Stock
             menge TYPE ck_lbkum,      " Total Stock (sum of above)
             salk3 TYPE salk3,        " Stock Value
             meins TYPE meins,        " Base Unit of Measure
             waers TYPE waers,        " Currency
           END OF lty_stock_detail,
           lty_stock_detail_t TYPE STANDARD TABLE OF lty_stock_detail WITH DEFAULT KEY.

    " Total: Per material/plant/date (aggregated)
    TYPES: BEGIN OF lty_stock_total,
             matnr TYPE matnr,        " Material
             werks TYPE werks_d,      " Plant
             budat TYPE budat,        " Date
             labst TYPE labst,        " Unrestricted Stock
             insme TYPE insme,        " Quality Inspection Stock
             speme TYPE speme,        " Blocked Stock
             menge TYPE ck_lbkum,      " Total Stock (sum of above)
             salk3 TYPE salk3,        " Stock Value
             meins TYPE meins,        " Base Unit of Measure
             waers TYPE waers,        " Currency
           END OF lty_stock_total,
           lty_stock_total_t TYPE STANDARD TABLE OF lty_stock_total WITH DEFAULT KEY.

    " --- API Methods ---
    CLASS-METHODS get_stocks
      IMPORTING
        !i_matnr_range   TYPE ranges_matnr_tt OPTIONAL
        !i_werks_range   TYPE ranges_werks_tt
        !i_budat_range   TYPE ranges_budat_tt
        !i_mtart_range   TYPE ranges_mtart_tt OPTIONAL  " Material Type filter
        !i_no_mska       TYPE abap_bool OPTIONAL  " Exclude sales order stock (MSKA/MSKAH)
        !i_no_mkol       TYPE abap_bool OPTIONAL  " Exclude consignment stock (MKOL/MKOLH)
        !i_no_mslb       TYPE abap_bool OPTIONAL  " Exclude subcontracting stock (MSLB/MSLBH)
      EXPORTING
        !et_stock_detail TYPE lty_stock_detail_t
      RETURNING
        VALUE(et_stock)  TYPE lty_stock_total_t .



    CLASS-METHODS check_move_match
      IMPORTING
        !ps_move  TYPE lty_move
        !ps_key   TYPE lty_calc_key
      CHANGING
        !cv_match TYPE abap_bool
        !cv_ssnum TYPE char20 .

    CLASS-METHODS get_period_end_date
      IMPORTING
        !p_gjahr       TYPE lfgja
        !p_monat       TYPE lfmon
      RETURNING
        VALUE(rv_date) TYPE datum .
  PROTECTED SECTION.
private section.
ENDCLASS.



CLASS ZCL_MM_STOCK_ON_DATE IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Static Public Method ZCL_MM_STOCK_ON_DATE=>CHECK_MOVE_MATCH
* +-------------------------------------------------------------------------------------------------+
* | [--->] PS_MOVE                        TYPE        LTY_MOVE
* | [--->] PS_KEY                         TYPE        LTY_CALC_KEY
* | [<-->] CV_MATCH                       TYPE        ABAP_BOOL
* | [<-->] CV_SSNUM                       TYPE        CHAR20
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD check_move_match.
    cv_match = abap_false.

    CASE ps_key-sobkz.
      WHEN ''. " Standard
        IF ps_move-sobkz = '' AND ps_move-lgort = ps_key-lgort.
          cv_match = abap_true.
        ENDIF.
      WHEN 'E'. " Sales Order
        IF ps_move-sobkz = 'E' AND ps_move-lgort = ps_key-lgort.
          cv_ssnum = |{ ps_move-mat_kdauf }{ ps_move-mat_kdpos }|. " Key from MSEG for E
          IF cv_ssnum = ps_key-ssnum.
            cv_match = abap_true.
          ENDIF.
        ENDIF.
      WHEN 'K'. " Consignment
        IF ps_move-sobkz = 'K' AND ps_move-lgort = ps_key-lgort AND ps_move-lifnr = ps_key-ssnum.
          cv_match = abap_true.
        ENDIF.
      WHEN 'O'. " Subcontracting (Ignore LGORT check, match Vendor)
        IF ps_move-sobkz = 'O' AND ps_move-lifnr = ps_key-ssnum.
          cv_match = abap_true.
        ENDIF.
    ENDCASE.
  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Static Public Method ZCL_MM_STOCK_ON_DATE=>GET_PERIOD_END_DATE
* +-------------------------------------------------------------------------------------------------+
* | [--->] P_GJAHR                        TYPE        LFGJA
* | [--->] P_MONAT                        TYPE        LFMON
* | [<-()] RV_DATE                        TYPE        DATUM
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_period_end_date.
    " Calcula el último día del periodo dado (LFGJA/LFMON)
    DATA: lv_first_day TYPE datum.

    lv_first_day(4) = p_gjahr.
    lv_first_day+4(2) = p_monat.
    lv_first_day+6(2) = '01'.

    CALL FUNCTION 'RP_LAST_DAY_OF_MONTHS'
      EXPORTING
        day_in            = lv_first_day
      IMPORTING
        last_day_of_month = rv_date.
  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Static Public Method ZCL_MM_STOCK_ON_DATE=>GET_STOCKS
* +-------------------------------------------------------------------------------------------------+
* | [--->] I_MATNR_RANGE                  TYPE        RANGES_MATNR_TT(optional)
* | [--->] I_WERKS_RANGE                  TYPE        RANGES_WERKS_TT
* | [--->] I_BUDAT_RANGE                  TYPE        RANGES_BUDAT_TT
* | [--->] I_MTART_RANGE                  TYPE        RANGES_MTART_TT(optional)
* | [--->] I_NO_MSKA                      TYPE        ABAP_BOOL(optional)
* | [--->] I_NO_MKOL                      TYPE        ABAP_BOOL(optional)
* | [--->] I_NO_MSLB                      TYPE        ABAP_BOOL(optional)
* | [<---] ET_STOCK_DETAIL                TYPE        LTY_STOCK_DETAIL_T
* | [<-()] ET_STOCK                       TYPE        LTY_STOCK_TOTAL_T
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD get_stocks.
  " Author: Carlos Vivó
  " Date: 2026.01.27
  "
  " PURPOSE:
  "   Calculate material stock for a given date range by combining current
  "   stock snapshots with historical movements (MSEG).
  "
  " ---------------------------------------------------------------------
  " ABBREVIATIONS / TERMINOLOGY:
  " ---------------------------------------------------------------------
  "   PS  = Selection Period (user-requested date range)
  "   PS0 = Start of Selection Period (first requested date)
  "   PS1 = End of Selection Period (last requested date)
  "
  "   A0  = Anchor 0: Last day of the period BEFORE PS0 (for forward rolling)
  "   A1  = Anchor 1: End of PS1's period OR today if current (for backward rolling)
  "   AF  = Actual/Final Anchor: The anchor chosen based on distance comparison
  "
  "   PF0 = MSEG range start date (from anchor or PS0)
  "   PF1 = MSEG range end date (to PS1 or anchor)
  "
  "   dist0 = Distance from A0 to PS0 (days to roll forward)
  "   dist1 = Distance from PS1 to A1 (days to roll backward)
  "
  " ---------------------------------------------------------------------
  " ALGORITHM STEPS:
  " ---------------------------------------------------------------------
  "   1. Parse Selection Period: Expand date ranges into individual dates
  "
  "   2. Calculate Global Anchor:
  "      - A0 = end of month before PS0
  "      - A1 = today (if current period) or end of PS1's month
  "      - Compare distances: if dist0 <= dist1 -> Roll Forward, else Backward
  "      - Set global MSEG range: [A0, PS1] or [PS0, A1]
  "
  "   3. Select Current Stock: MARD, MSKA, MKOL, MSLB (optional exclusion)
  "
  "   4. Identify Stale Keys: If key's current period < PS0 -> constant stock
  "
  "   5. Select Historical Data: MARDH, MSKAH, MKOLH, MSLBH for active keys
  "
  "   6. Determine Anchor per Key:
  "      - Find first entry in lt_combined where period_end >= A0_ideal
  "      - Handle Pre-History Zero: if first history > PS1 -> stock = 0
  "
  "   7. Fetch MSEG: Single query with global date range
  "
  "   8. Rolling Calculation per Key:
  "      - Forward: Start at anchor, apply movements day by day until PS1
  "      - Backward: Start at anchor, reverse movements day by day until PS0
  "      - Output: Stock per material/plant/date
  "
  " ====================================================================="

  " === DATA DEFINITIONS ===
  DATA: lt_dates_req TYPE STANDARD TABLE OF datum,
        lt_out_det   TYPE STANDARD TABLE OF lty_stock_detail,
        lt_out_tot   TYPE STANDARD TABLE OF lty_stock_total.

  DATA: ls_rng      LIKE LINE OF i_budat_range,
        lv_date_idx TYPE datum,
        lv_ps0      TYPE datum, " Start of Selection Period
        lv_ps1      TYPE datum. " End of Selection Period

  " Key Definitions & Data
  TYPES: BEGIN OF lty_key_data,
           werks    TYPE werks_d,
           matnr    TYPE matnr,
           lgort    TYPE lgort_d,
           sobkz    TYPE sobkz,
           ssnum    TYPE char20,
           labst    TYPE labst,       " Unrestricted Stock
           insme    TYPE insme,       " Quality Inspection Stock
           speme    TYPE speme,       " Blocked Stock
           lfgja    TYPE lfgja,       " Current Period Year
           lfmon    TYPE lfmon,       " Current Period Month
           is_stale TYPE abap_bool,   " Optimization Flag: Current Period < PS0
         END OF lty_key_data.
  DATA: lt_keys TYPE HASHED TABLE OF lty_key_data
                WITH UNIQUE KEY werks matnr lgort sobkz ssnum.

  " Combined History + Current
  TYPES: BEGIN OF lty_combined_data,
           werks      TYPE werks_d,
           matnr      TYPE matnr,
           lgort      TYPE lgort_d,
           sobkz      TYPE sobkz,
           ssnum      TYPE char20,
           labst      TYPE labst,
           insme      TYPE insme,
           speme      TYPE speme,
           period_end TYPE datum,
           source     TYPE char1, " 'H'istory, 'C'urrent
         END OF lty_combined_data.
  DATA: lt_combined TYPE SORTED TABLE OF lty_combined_data
                    WITH NON-UNIQUE KEY werks matnr lgort sobkz ssnum period_end.

  " Processing decision per key
  TYPES: BEGIN OF lty_key_decision,
           key       TYPE lty_key_data,
           af_date   TYPE datum,
           af_labst  TYPE labst,
           af_insme  TYPE insme,
           af_speme  TYPE speme,
           skip_mseg TYPE abap_bool,
         END OF lty_key_decision.
  DATA: lt_decis TYPE STANDARD TABLE OF lty_key_decision.

  " Global anchor calculation variables
  DATA: lv_curr_gjahr TYPE lfgja,
        lv_curr_monat TYPE lfmon,
        lv_curr_start TYPE datum.

  DATA: lv_a0_ideal   TYPE datum,
        lv_a1_ideal   TYPE datum,
        lv_global_af  TYPE datum,    " Global anchor date (A0 or A1)
        lv_global_pf0 TYPE datum,
        lv_global_pf1 TYPE datum.

  " Rolling variables
  DATA: lv_ssnum_tmp TYPE char20,
        lv_is_match  TYPE abap_bool,
        lv_total     TYPE ck_lbkum,  " Must match menge type in output structure
        lv_sign      TYPE decfloat16,  " Sign multiplier: 1 or -1 (decimal to preserve menge precision)
        lv_delta     TYPE menge_d.     " Movement delta with decimals

  " First history lookup variables (for anchor fallback)
  DATA: lv_first_hist_found TYPE abap_bool,
        lv_first_hist_date  TYPE datum,
        lv_first_hist_labst TYPE labst,
        lv_first_hist_insme TYPE insme,
        lv_first_hist_speme TYPE speme.

  " ---------------------------------------------------------------------
  " 1. DETERMINE SELECTION PERIOD (PS) - [PS0, PS1]
  " ---------------------------------------------------------------------
  LOOP AT i_budat_range INTO ls_rng.
    IF ls_rng-option = 'EQ'.
      APPEND ls_rng-low TO lt_dates_req.
    ELSEIF ls_rng-option = 'BT'.
      lv_date_idx = ls_rng-low.
      WHILE lv_date_idx <= ls_rng-high.
        APPEND lv_date_idx TO lt_dates_req.
        lv_date_idx = lv_date_idx + 1.
      ENDWHILE.
    ENDIF.
  ENDLOOP.
  SORT lt_dates_req ASCENDING.
  DELETE ADJACENT DUPLICATES FROM lt_dates_req.
  IF lt_dates_req IS INITIAL. RETURN. ENDIF.

  lv_ps0 = lt_dates_req[ 1 ].
  lv_ps1 = lt_dates_req[ lines( lt_dates_req ) ].

  " Determine Current Period Start
  lv_curr_gjahr = sy-datum(4).
  lv_curr_monat = sy-datum+4(2).
  lv_curr_start = |{ lv_curr_gjahr }{ lv_curr_monat WIDTH = 2 ALIGN = RIGHT PAD = '0' }01|.

  " ---------------------------------------------------------------------
  " 2. CALCULATE GLOBAL ANCHOR (ONCE, based on PS)
  " ---------------------------------------------------------------------
  " A0 = Last day of period prior to PS0
  DATA(lv_ps0_gjahr) = lv_ps0(4).
  DATA(lv_ps0_monat) = lv_ps0+4(2).
  IF lv_ps0_monat = '01'.
    lv_ps0_gjahr = lv_ps0_gjahr - 1.
    lv_ps0_monat = '12'.
  ELSE.
    lv_ps0_monat = lv_ps0_monat - 1.
  ENDIF.
  lv_a0_ideal = zcl_mm_stock_on_date=>get_period_end_date( p_gjahr = lv_ps0_gjahr p_monat = lv_ps0_monat ).

  " A1: If PS1 in Current -> Today. Else -> End of PS1 Period.
  IF lv_ps1 >= lv_curr_start.
    lv_a1_ideal = sy-datum.
  ELSE.
    lv_a1_ideal = zcl_mm_stock_on_date=>get_period_end_date( p_gjahr = lv_ps1(4) p_monat = lv_ps1+4(2) ).
  ENDIF.

  " Calculate distances and choose global anchor
  DATA(lv_dist0) = lv_ps0 - lv_a0_ideal.    " Distance from A0 to PS0
  DATA(lv_dist1) = lv_a1_ideal - lv_ps1.    " Distance from PS1 to A1

  " Choose global anchor based on shortest distance
  " If dist0 <= dist1: Roll Forward from A0, PF = [A0, PS1]
  " Else: Roll Backward from A1, PF = [PS0, A1]
  IF lv_dist0 <= lv_dist1.
    lv_global_af = lv_a0_ideal.   " Global anchor = A0 (roll forward)
    lv_global_pf0 = lv_a0_ideal.
    lv_global_pf1 = lv_ps1.
  ELSE.
    lv_global_af = lv_a1_ideal.   " Global anchor = A1 (roll backward)
    lv_global_pf0 = lv_ps0.
    lv_global_pf1 = lv_a1_ideal.
  ENDIF.

  " 3. SELECT FROM CURRENT TABLES
  " ---------------------------------------------------------------------

  " MARD - with optional MTART filter via JOIN
  IF i_mtart_range IS NOT INITIAL.
    SELECT d~matnr, d~werks, d~lgort, d~lfgja, d~lfmon,
           d~labst, d~insme, d~speme
      FROM mard AS d
      INNER JOIN mara AS m ON m~matnr = d~matnr
      INTO TABLE @DATA(lt_mard)
      WHERE d~matnr IN @i_matnr_range
        AND d~werks IN @i_werks_range
        AND m~mtart IN @i_mtart_range.
  ELSE.
    SELECT matnr, werks, lgort, lfgja, lfmon,
           labst, insme, speme
      FROM mard INTO TABLE @lt_mard
      WHERE matnr IN @i_matnr_range AND werks IN @i_werks_range.
  ENDIF.

  LOOP AT lt_mard INTO DATA(ls_mard).
    INSERT VALUE #( werks = ls_mard-werks matnr = ls_mard-matnr lgort = ls_mard-lgort
                    sobkz = '' ssnum = ''
                    labst = ls_mard-labst insme = ls_mard-insme speme = ls_mard-speme
                    lfgja = ls_mard-lfgja lfmon = ls_mard-lfmon ) INTO TABLE lt_keys.
  ENDLOOP.

  IF i_no_mska IS INITIAL.
    " MSKA - Stock with Sales Order (E)
    " kalab=unrestricted, kains=quality, kaspe=blocked
    IF i_mtart_range IS NOT INITIAL.
      SELECT s~matnr, s~werks, s~lgort, s~vbeln, s~posnr, s~lfgja, s~lfmon,
             s~kalab, s~kains, s~kaspe
        FROM mska AS s
        INNER JOIN mara AS m ON m~matnr = s~matnr
        INTO TABLE @DATA(lt_mska)
        WHERE s~matnr IN @i_matnr_range
          AND s~werks IN @i_werks_range
          AND s~sobkz = 'E'
          AND m~mtart IN @i_mtart_range.
    ELSE.
      SELECT matnr, werks, lgort, vbeln, posnr, lfgja, lfmon,
             kalab, kains, kaspe
        FROM mska INTO TABLE @lt_mska
        WHERE matnr IN @i_matnr_range AND werks IN @i_werks_range AND sobkz = 'E'.
    ENDIF.

    LOOP AT lt_mska INTO DATA(ls_mska).
      DATA(lv_ssnum_e) = |{ ls_mska-vbeln }{ ls_mska-posnr }|.
      INSERT VALUE #( werks = ls_mska-werks matnr = ls_mska-matnr lgort = ls_mska-lgort
                      sobkz = 'E' ssnum = lv_ssnum_e
                      labst = ls_mska-kalab insme = ls_mska-kains speme = ls_mska-kaspe
                      lfgja = ls_mska-lfgja lfmon = ls_mska-lfmon ) INTO TABLE lt_keys.
    ENDLOOP.
  ENDIF.

  IF i_no_mkol IS INITIAL.
    " MKOL - Consignment Stock (K)
    " slabs=unrestricted, sinsm=quality, sspem=blocked
    IF i_mtart_range IS NOT INITIAL.
      SELECT k~matnr, k~werks, k~lgort, k~lifnr, k~lfgja, k~lfmon,
             k~slabs, k~sinsm, k~sspem
        FROM mkol AS k
        INNER JOIN mara AS m ON m~matnr = k~matnr
        INTO TABLE @DATA(lt_mkol)
        WHERE k~matnr IN @i_matnr_range
          AND k~werks IN @i_werks_range
          AND k~sobkz = 'K'
          AND m~mtart IN @i_mtart_range.
    ELSE.
      SELECT matnr, werks, lgort, lifnr, lfgja, lfmon,
             slabs, sinsm, sspem
        FROM mkol INTO TABLE @lt_mkol
        WHERE matnr IN @i_matnr_range AND werks IN @i_werks_range AND sobkz = 'K'.
    ENDIF.

    LOOP AT lt_mkol INTO DATA(ls_mkol).
      INSERT VALUE #( werks = ls_mkol-werks matnr = ls_mkol-matnr lgort = ls_mkol-lgort
                      sobkz = 'K' ssnum = ls_mkol-lifnr
                      labst = ls_mkol-slabs insme = ls_mkol-sinsm speme = ls_mkol-sspem
                      lfgja = ls_mkol-lfgja lfmon = ls_mkol-lfmon ) INTO TABLE lt_keys.
    ENDLOOP.
  ENDIF.

  IF i_no_mslb IS INITIAL.
    " MSLB - Subcontracting Stock (O)
    " lblab=unrestricted, lbins=quality (no blocked field)
    IF i_mtart_range IS NOT INITIAL.
      SELECT b~matnr, b~werks, b~lifnr, b~lfgja, b~lfmon,
             b~lblab, b~lbins
        FROM mslb AS b
        INNER JOIN mara AS m ON m~matnr = b~matnr
        INTO TABLE @DATA(lt_mslb)
        WHERE b~matnr IN @i_matnr_range
          AND b~werks IN @i_werks_range
          AND b~sobkz = 'O'
          AND m~mtart IN @i_mtart_range.
    ELSE.
      SELECT matnr, werks, lifnr, lfgja, lfmon,
             lblab, lbins
        FROM mslb INTO TABLE @lt_mslb
        WHERE matnr IN @i_matnr_range AND werks IN @i_werks_range AND sobkz = 'O'.
    ENDIF.

    LOOP AT lt_mslb INTO DATA(ls_mslb).
      INSERT VALUE #( werks = ls_mslb-werks matnr = ls_mslb-matnr lgort = ''
                      sobkz = 'O' ssnum = ls_mslb-lifnr
                      labst = ls_mslb-lblab insme = ls_mslb-lbins speme = 0
                      lfgja = ls_mslb-lfgja lfmon = ls_mslb-lfmon ) INTO TABLE lt_keys.
    ENDLOOP.
  ENDIF.

  IF lt_keys IS INITIAL. RETURN. ENDIF.

  " ---------------------------------------------------------------------
  " 4. DETERMINE STALE KEYS (Current Period < PS0 -> Constant Stock)
  " ---------------------------------------------------------------------
  FIELD-SYMBOLS: <fs_key> LIKE LINE OF lt_keys.
  LOOP AT lt_keys ASSIGNING <fs_key>.
    DATA(lv_key_period_end) = zcl_mm_stock_on_date=>get_period_end_date( p_gjahr = <fs_key>-lfgja p_monat = <fs_key>-lfmon ).
    IF lv_key_period_end < lv_ps0.
      <fs_key>-is_stale = abap_true.
    ELSE.
      <fs_key>-is_stale = abap_false.
    ENDIF.
  ENDLOOP.

  " Create Active Keys list for History Selection (non-stale keys only)
  DATA: lt_keys_active TYPE STANDARD TABLE OF lty_key_data.
  LOOP AT lt_keys INTO DATA(ls_k_act) WHERE is_stale = abap_false.
    APPEND ls_k_act TO lt_keys_active.
  ENDLOOP.

  " ---------------------------------------------------------------------
  " 5. SELECT HISTORY (ONLY FOR ACTIVE KEYS, only if PS touches history)
  " ---------------------------------------------------------------------
  IF lv_ps0 < lv_curr_start AND lt_keys_active IS NOT INITIAL.

    " MARDH
    SELECT matnr, werks, lgort, lfgja, lfmon,
           labst, umlme, insme, einme, speme, retme
      FROM mardh INTO TABLE @DATA(lt_mardh)
      FOR ALL ENTRIES IN @lt_keys_active
      WHERE matnr = @lt_keys_active-matnr AND werks = @lt_keys_active-werks AND lgort = @lt_keys_active-lgort.

    LOOP AT lt_mardh INTO DATA(ls_rh_raw).
      INSERT VALUE #( werks = ls_rh_raw-werks matnr = ls_rh_raw-matnr lgort = ls_rh_raw-lgort sobkz = '' ssnum = ''
                      labst = ls_rh_raw-labst insme = ls_rh_raw-insme speme = ls_rh_raw-speme
                      source = 'H'
                      period_end = zcl_mm_stock_on_date=>get_period_end_date( p_gjahr = ls_rh_raw-lfgja p_monat = ls_rh_raw-lfmon )
                    ) INTO TABLE lt_combined.
    ENDLOOP.

    IF i_no_mska IS INITIAL.
      " MSKAH
      SELECT matnr, werks, lgort, vbeln, posnr, lfgja, lfmon,
             kalab, kains, kaspe
        FROM mskah INTO TABLE @DATA(lt_mskah)
        FOR ALL ENTRIES IN @lt_keys_active
        WHERE matnr = @lt_keys_active-matnr AND werks = @lt_keys_active-werks AND lgort = @lt_keys_active-lgort AND sobkz = @lt_keys_active-sobkz.

      LOOP AT lt_mskah INTO DATA(ls_kh_raw).
        lv_ssnum_e = |{ ls_kh_raw-vbeln }{ ls_kh_raw-posnr }|.
        INSERT VALUE #( werks = ls_kh_raw-werks matnr = ls_kh_raw-matnr lgort = ls_kh_raw-lgort sobkz = 'E' ssnum = lv_ssnum_e
                        labst = ls_kh_raw-kalab insme = ls_kh_raw-kains speme = ls_kh_raw-kaspe
                        source = 'H'
                        period_end = zcl_mm_stock_on_date=>get_period_end_date( p_gjahr = ls_kh_raw-lfgja p_monat = ls_kh_raw-lfmon )
                      ) INTO TABLE lt_combined.
      ENDLOOP.
    ENDIF.

    IF i_no_mkol IS INITIAL.
      " MKOLH
      SELECT matnr, werks, lgort, lifnr, lfgja, lfmon,
             slabs, sinsm, seinm, sspem
        FROM mkolh INTO TABLE @DATA(lt_mkolh)
        FOR ALL ENTRIES IN @lt_keys_active
        WHERE matnr = @lt_keys_active-matnr AND werks = @lt_keys_active-werks AND lgort = @lt_keys_active-lgort AND sobkz = @lt_keys_active-sobkz.

      LOOP AT lt_mkolh INTO DATA(ls_lh_raw).
        INSERT VALUE #( werks = ls_lh_raw-werks matnr = ls_lh_raw-matnr lgort = ls_lh_raw-lgort sobkz = 'K' ssnum = ls_lh_raw-lifnr
                       labst = ls_lh_raw-slabs insme = ls_lh_raw-sinsm speme = ls_lh_raw-sspem
                       source = 'H'
                       period_end = zcl_mm_stock_on_date=>get_period_end_date( p_gjahr = ls_lh_raw-lfgja p_monat = ls_lh_raw-lfmon )
                     ) INTO TABLE lt_combined.
      ENDLOOP.
    ENDIF.

    IF i_no_mslb IS INITIAL.
      " MSLBH
      SELECT matnr, werks, lifnr, lfgja, lfmon,
             lblab, lbins
        FROM mslbh INTO TABLE @DATA(lt_mslbh)
        FOR ALL ENTRIES IN @lt_keys_active
        WHERE matnr = @lt_keys_active-matnr AND werks = @lt_keys_active-werks AND sobkz = @lt_keys_active-sobkz.

      LOOP AT lt_mslbh INTO DATA(ls_bh_raw).
        INSERT VALUE #( werks = ls_bh_raw-werks matnr = ls_bh_raw-matnr lgort = '' sobkz = 'O' ssnum = ls_bh_raw-lifnr
                       labst = ls_bh_raw-lblab insme = ls_bh_raw-lbins speme = 0
                       source = 'H'
                       period_end = zcl_mm_stock_on_date=>get_period_end_date( p_gjahr = ls_bh_raw-lfgja p_monat = ls_bh_raw-lfmon )
                     ) INTO TABLE lt_combined.
      ENDLOOP.
    ENDIF.
  ENDIF.

  " Add Current Stock entries for active keys (period_end = today for rolling purposes)
  LOOP AT lt_keys_active INTO DATA(ls_k_active).
    INSERT VALUE #( werks = ls_k_active-werks matnr = ls_k_active-matnr lgort = ls_k_active-lgort
                    sobkz = ls_k_active-sobkz ssnum = ls_k_active-ssnum
                    labst = ls_k_active-labst insme = ls_k_active-insme speme = ls_k_active-speme
                    source = 'C'
                    period_end = sy-datum
                  ) INTO TABLE lt_combined.
  ENDLOOP.

  " ---------------------------------------------------------------------
  " 6. DETERMINE ANCHOR & DECISION PER KEY (Simplified)
  " ---------------------------------------------------------------------
  DATA: lt_matnr_mseg TYPE RANGE OF matnr.

  LOOP AT lt_keys INTO DATA(ls_k).

    " --- STALE KEY: Constant stock, skip MSEG ---
    IF ls_k-is_stale = abap_true.
      APPEND VALUE #( key = ls_k af_date = sy-datum
                      af_labst = ls_k-labst af_insme = ls_k-insme af_speme = ls_k-speme
                      skip_mseg = abap_true ) TO lt_decis.
      CONTINUE.
    ENDIF.

    " --- Find stock at global anchor for this key ---
    DATA(lv_found) = abap_false.
    DATA(lv_pre_history_zero) = abap_false.
    DATA(lv_af_date) = lv_global_af.
    DATA(lv_af_labst) = CONV labst( 0 ).
    DATA(lv_af_insme) = CONV insme( 0 ).
    DATA(lv_af_speme) = CONV speme( 0 ).

    LOOP AT lt_combined INTO DATA(ls_c)
         WHERE werks = ls_k-werks AND matnr = ls_k-matnr
           AND lgort = ls_k-lgort AND sobkz = ls_k-sobkz AND ssnum = ls_k-ssnum.

      " Check for Pre-History Zero: if first entry is after PS1
      IF sy-tabix = 1 AND ls_c-source = 'H' AND ls_c-period_end > lv_ps1.
        " Material didn't exist during selection period -> Stock 0, Skip MSEG
        APPEND VALUE #( key = ls_k af_date = lv_global_af
                        af_labst = 0 af_insme = 0 af_speme = 0
                        skip_mseg = abap_true ) TO lt_decis.
        lv_pre_history_zero = abap_true.
        EXIT.
      ENDIF.

      " Find first HISTORICAL entry >= global anchor (stock at anchor period)
      " Skip Current entries (source='C') - they have period_end = sy-datum
      IF ls_c-period_end >= lv_global_af AND ls_c-source = 'H'.
        lv_af_date = ls_c-period_end.  " Use actual period_end from history
        lv_af_labst = ls_c-labst.
        lv_af_insme = ls_c-insme.
        lv_af_speme = ls_c-speme.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    " If already handled (Pre-History Zero), continue
    IF lv_pre_history_zero = abap_true.
      CONTINUE.
    ENDIF.


    " If no anchor found at global_af, handle based on roll direction
    IF lv_found = abap_false.
      " Check if we were supposed to roll forward (global_af = A0)
      IF lv_global_af = lv_a0_ideal.
        " Rolling forward but no history at A0. Find first available history entry.
        CLEAR: lv_first_hist_found, lv_first_hist_date, lv_first_hist_labst,
               lv_first_hist_insme, lv_first_hist_speme.

        LOOP AT lt_combined INTO ls_c
             WHERE werks = ls_k-werks AND matnr = ls_k-matnr
               AND lgort = ls_k-lgort AND sobkz = ls_k-sobkz AND ssnum = ls_k-ssnum
               AND source = 'H'.  " Only consider historical entries
          lv_first_hist_found = abap_true.
          lv_first_hist_date = ls_c-period_end.
          lv_first_hist_labst = ls_c-labst.
          lv_first_hist_insme = ls_c-insme.
          lv_first_hist_speme = ls_c-speme.
          EXIT. " Take the first one (sorted by period_end)
        ENDLOOP.

        IF lv_first_hist_found = abap_true AND lv_first_hist_date <= lv_ps1.
          " Use first available history as anchor
          lv_af_date = lv_first_hist_date.
          lv_af_labst = lv_first_hist_labst.
          lv_af_insme = lv_first_hist_insme.
          lv_af_speme = lv_first_hist_speme.
        ELSE.
          " No history before PS1 - assume stock was 0 at A0 and roll forward
          lv_af_date = lv_global_af.
          lv_af_labst = 0.
          lv_af_insme = 0.
          lv_af_speme = 0.
        ENDIF.
      ELSE.
        " Rolling backward - use current stock as fallback (original behavior)
        lv_af_date = sy-datum.
        lv_af_labst = ls_k-labst.
        lv_af_insme = ls_k-insme.
        lv_af_speme = ls_k-speme.
      ENDIF.
    ENDIF.

    APPEND VALUE #( key = ls_k af_date = lv_af_date
                    af_labst = lv_af_labst af_insme = lv_af_insme af_speme = lv_af_speme
                    skip_mseg = abap_false ) TO lt_decis.

    " Add material to MSEG filter
    APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_k-matnr ) TO lt_matnr_mseg.
  ENDLOOP.

  SORT lt_matnr_mseg BY low.
  DELETE ADJACENT DUPLICATES FROM lt_matnr_mseg.

  " ---------------------------------------------------------------------
  " 7. FETCH MSEG ONCE (Global Range)
  " ---------------------------------------------------------------------
  DATA: lt_moves TYPE SORTED TABLE OF lty_move WITH NON-UNIQUE KEY werks matnr budat.

  IF lt_matnr_mseg IS NOT INITIAL.
    SELECT mblnr, mjahr, zeile, budat_mkpf AS budat, shkzg, matnr,
           werks, lgort, sobkz, lifnr, mat_kdauf, mat_kdpos, insmk, menge
      FROM mseg
      INTO CORRESPONDING FIELDS OF TABLE @lt_moves
      WHERE budat_mkpf >= @lv_global_pf0
        AND budat_mkpf <= @lv_global_pf1
        AND matnr IN @lt_matnr_mseg
        AND werks IN @i_werks_range.
  ENDIF.

  " ---------------------------------------------------------------------
  " 8. CALCULATE STOCK (ROLLING)
  " ---------------------------------------------------------------------
  LOOP AT lt_decis INTO DATA(ls_d).
    DATA ls_calc_key TYPE lty_calc_key.
    MOVE-CORRESPONDING ls_d-key TO ls_calc_key.

    " --- Keys with skip_mseg = true: Output constant stock for all dates ---
    IF ls_d-skip_mseg = abap_true.
      LOOP AT lt_dates_req INTO DATA(lv_d).
        lv_total = ls_d-af_labst + ls_d-af_insme + ls_d-af_speme.
        INSERT VALUE #( werks = ls_d-key-werks matnr = ls_d-key-matnr budat = lv_d
                        lgort = ls_d-key-lgort sobkz = ls_d-key-sobkz ssnum = ls_d-key-ssnum
                        labst = ls_d-af_labst insme = ls_d-af_insme speme = ls_d-af_speme
                        menge = lv_total ) INTO TABLE lt_out_det.
      ENDLOOP.
      CONTINUE.
    ENDIF.

    " --- Active keys: Roll from anchor ---
    DATA(lv_curr_labst) = ls_d-af_labst.
    DATA(lv_curr_insme) = ls_d-af_insme.
    DATA(lv_curr_speme) = ls_d-af_speme.
    DATA(lv_cursor) = ls_d-af_date.

    IF lv_cursor <= lv_ps0.
      " Anchor is <= Start. Roll FORWARD.
      DATA(lv_run_date) = lv_cursor.

      " Record stock on PS0 if cursor = PS0 (before rolling)
      IF lv_cursor = lv_ps0.
        lv_total = lv_curr_labst + lv_curr_insme + lv_curr_speme.
        INSERT VALUE #( werks = ls_d-key-werks matnr = ls_d-key-matnr budat = lv_ps0
                        lgort = ls_d-key-lgort sobkz = ls_d-key-sobkz ssnum = ls_d-key-ssnum
                        labst = lv_curr_labst insme = lv_curr_insme speme = lv_curr_speme
                        menge = lv_total ) INTO TABLE lt_out_det.
      ENDIF.

      WHILE lv_run_date < lv_ps1.
        lv_run_date = lv_run_date + 1.

        " Apply movements of this day
        LOOP AT lt_moves INTO DATA(ls_m) USING KEY primary_key
             WHERE werks = ls_d-key-werks AND matnr = ls_d-key-matnr AND budat = lv_run_date.
          zcl_mm_stock_on_date=>check_move_match( EXPORTING ps_key = ls_calc_key ps_move = ls_m
                                                  CHANGING cv_match = lv_is_match cv_ssnum = lv_ssnum_tmp ).
          CHECK lv_is_match = abap_true.
          lv_sign = COND decfloat16( WHEN ls_m-shkzg = 'S' THEN 1 ELSE -1 ).
          lv_delta = ls_m-menge * lv_sign.
          " Apply to correct stock type based on INSMK
          CASE ls_m-insmk.
            WHEN '' OR 'F'.
              lv_curr_labst = lv_curr_labst + lv_delta.
            WHEN 'X' OR '2'.
              lv_curr_insme = lv_curr_insme + lv_delta.
            WHEN 'S' OR '3'.
              lv_curr_speme = lv_curr_speme + lv_delta.
          ENDCASE.
        ENDLOOP.

        " If inside Request Range, save to detail table
        IF lv_run_date >= lv_ps0 AND lv_run_date <= lv_ps1.
          lv_total = lv_curr_labst + lv_curr_insme + lv_curr_speme.
          INSERT VALUE #( werks = ls_d-key-werks matnr = ls_d-key-matnr budat = lv_run_date
                          lgort = ls_d-key-lgort sobkz = ls_d-key-sobkz ssnum = ls_d-key-ssnum
                          labst = lv_curr_labst insme = lv_curr_insme speme = lv_curr_speme
                          menge = lv_total ) INTO TABLE lt_out_det.
        ENDIF.
      ENDWHILE.

    ELSE.
      " Anchor is in Future (> PS0). Roll BACKWARD.
      lv_run_date = lv_cursor.

      WHILE lv_run_date >= lv_ps0.
        " If current run_date is inside Range, Record it to detail table.
        IF lv_run_date <= lv_ps1.
          lv_total = lv_curr_labst + lv_curr_insme + lv_curr_speme.
          INSERT VALUE #( werks = ls_d-key-werks matnr = ls_d-key-matnr budat = lv_run_date
                          lgort = ls_d-key-lgort sobkz = ls_d-key-sobkz ssnum = ls_d-key-ssnum
                          labst = lv_curr_labst insme = lv_curr_insme speme = lv_curr_speme
                          menge = lv_total ) INTO TABLE lt_out_det.
        ENDIF.

        " Reverse movements of this day
        LOOP AT lt_moves INTO ls_m USING KEY primary_key
             WHERE werks = ls_d-key-werks AND matnr = ls_d-key-matnr AND budat = lv_run_date.
          zcl_mm_stock_on_date=>check_move_match( EXPORTING ps_key = ls_calc_key ps_move = ls_m
                                                  CHANGING cv_match = lv_is_match cv_ssnum = lv_ssnum_tmp ).
          CHECK lv_is_match = abap_true.
          lv_sign = COND decfloat16( WHEN ls_m-shkzg = 'S' THEN -1 ELSE 1 ). " Inverse for backward rolling
          lv_delta = ls_m-menge * lv_sign.
          " Apply to correct stock type based on INSMK
          CASE ls_m-insmk.
            WHEN '' OR 'F'.
              lv_curr_labst = lv_curr_labst + lv_delta.
            WHEN 'X' OR '2'.
              lv_curr_insme = lv_curr_insme + lv_delta.
            WHEN 'S' OR '3'.
              lv_curr_speme = lv_curr_speme + lv_delta.
          ENDCASE.
        ENDLOOP.

        lv_run_date = lv_run_date - 1.
      ENDWHILE.
    ENDIF.

  ENDLOOP.

  " ---------------------------------------------------------------------
  " 8b. AGGREGATE DETAIL INTO TOTAL
  " ---------------------------------------------------------------------
  LOOP AT lt_out_det INTO DATA(ls_det)
       GROUP BY ( matnr = ls_det-matnr werks = ls_det-werks budat = ls_det-budat )
       ASSIGNING FIELD-SYMBOL(<grp>).
    DATA(lv_sum_labst) = REDUCE labst( INIT s1 = CONV labst( 0 )
                                       FOR m IN GROUP <grp> NEXT s1 = s1 + m-labst ).
    DATA(lv_sum_insme) = REDUCE insme( INIT s2 = CONV insme( 0 )
                                       FOR m IN GROUP <grp> NEXT s2 = s2 + m-insme ).
    DATA(lv_sum_speme) = REDUCE speme( INIT s3 = CONV speme( 0 )
                                       FOR m IN GROUP <grp> NEXT s3 = s3 + m-speme ).
    DATA(lv_sum_menge) = REDUCE ck_lbkum( INIT s4 = CONV ck_lbkum( 0 )
                                          FOR m IN GROUP <grp> NEXT s4 = s4 + m-menge ).
    INSERT VALUE #( matnr = <grp>-matnr werks = <grp>-werks budat = <grp>-budat
                    labst = lv_sum_labst insme = lv_sum_insme speme = lv_sum_speme
                    menge = lv_sum_menge ) INTO TABLE lt_out_tot.
  ENDLOOP.

  et_stock_detail = lt_out_det.
  et_stock = lt_out_tot.

  " ---------------------------------------------------------------------
  " 9. VALUATE STOCK (using current valuation)
  " ---------------------------------------------------------------------

  " Get valuation data from MBEW
  SELECT matnr, bwkey, vprsv, verpr, stprs, peinh FROM mbew
    FOR ALL ENTRIES IN @et_stock
    WHERE matnr EQ @et_stock-matnr
      AND bwkey EQ @et_stock-werks
    INTO TABLE @DATA(lt_mbew).

  " Get base unit of measure from MARA
  SELECT matnr, meins FROM mara
    FOR ALL ENTRIES IN @et_stock
    WHERE matnr EQ @et_stock-matnr
    INTO TABLE @DATA(lt_mara).

  " Get currency from company code (T001K -> T001)
  SELECT t001k~bwkey, t001~waers FROM t001k
    INNER JOIN t001 ON t001~bukrs = t001k~bukrs
    WHERE t001k~bwkey IN @i_werks_range
    INTO TABLE @DATA(lt_waers).

  " Valuate detail entries
  LOOP AT et_stock_detail ASSIGNING FIELD-SYMBOL(<detail>).
    TRY.
        DATA(ls_mbew) = lt_mbew[ matnr = <detail>-matnr bwkey = <detail>-werks ].
        <detail>-salk3 = COND #( WHEN ls_mbew-vprsv EQ 'V'
                                 THEN ( ls_mbew-verpr * <detail>-menge / ls_mbew-peinh )
                                 ELSE ( ls_mbew-stprs * <detail>-menge / ls_mbew-peinh ) ).
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
    TRY.
        <detail>-meins = lt_mara[ matnr = <detail>-matnr ]-meins.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
    TRY.
        <detail>-waers = lt_waers[ bwkey = <detail>-werks ]-waers.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
  ENDLOOP.

  " Valuate total entries
  LOOP AT et_stock ASSIGNING FIELD-SYMBOL(<total>).
    TRY.
        ls_mbew = lt_mbew[ matnr = <total>-matnr bwkey = <total>-werks ].
        <total>-salk3 = COND #( WHEN ls_mbew-vprsv EQ 'V'
                                THEN ( ls_mbew-verpr * <total>-menge / ls_mbew-peinh )
                                ELSE ( ls_mbew-stprs * <total>-menge / ls_mbew-peinh ) ).
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
    TRY.
        <total>-meins = lt_mara[ matnr = <total>-matnr ]-meins.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
    TRY.
        <total>-waers = lt_waers[ bwkey = <total>-werks ]-waers.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
  ENDLOOP.

ENDMETHOD.
ENDCLASS.