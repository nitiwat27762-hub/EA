//+------------------------------------------------------------------+
//|                                  Seven_Lines_Exhaustion_Ind.mq5  |
//|                     Converted from EA v8.80 to Custom Indicator  |
//|   v8.81: Live Floating Z-Score (Top & Bottom of Current Candle)  |
//|   v8.82: Non-Repaint History Engine + Live Bar Preview           |
//+------------------------------------------------------------------+
//
// 📝 v8.82 CHANGELOG
//  1. แก้ Repaint: ล็อกจุดเริ่มจำลองไว้ตายตัว และเก็บสถานะ (SimState) ของแท่งปิดล่าสุด
//     แท่งใหม่จะเดินต่อจากสถานะเดิมทีละแท่ง → สัญญาณย้อนหลังไม่เปลี่ยนอีก
//  2. แท่งปัจจุบันประเมินสัญญาณแบบ "พรีวิว" ทุก Tick บนสำเนาสถานะ (ไม่บันทึกถาวร)
//     และใช้ตัวจับเวลา No New High/Low (InpCounterWait_Sec / InpReEntryWait_Sec) + Crisis ยิงทันที
//     สัญญาณถาวรถูกยืนยันเมื่อแท่งปิดด้วย OHLC สุดท้าย
//  3. แก้ป้ายข้อความค้าง: ลบป้ายทั้งหมดทุกครั้งที่รีเซ็ตการคำนวณ / ป้ายแท่งสดแยกชื่อและลบทุก Tick
//  4. คำนวณเส้นทั้ง 7 เฉพาะแท่งที่เปลี่ยน (prev_calculated) + เก็บ StdDev ใน Buffer คำนวณ
//  5. SL ของสล็อตจำลองขยับได้ทางเดียว (Ratchet) ไม่ถอยหลังเมื่อเปลี่ยนชั้นโล่
//  6. ตรวจสอบค่า Input ใน OnInit + ตั้ง PLOT_DRAW_BEGIN ให้เส้นเริ่มวาดพร้อมกัน
//  7. ข้อความ Dashboard ใช้ค่าจาก Input จริง (ไม่ hardcode 5,000 / 500 ฯลฯ)
//
#property copyright "Commander's Quant System"
#property version   "8.82"
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots   15

//--- 1. ตั้งค่าการวาดเส้นทั้ง 7 เส้น (Plots 0-6)
#property indicator_label1  "Main (SMA)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

#property indicator_label2  "L1 (EMA)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDeepSkyBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "L2 (LWMA)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "L3 (HMA)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrMagenta
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

#property indicator_label5  "L4 (CG_LSMA)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrHotPink
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#property indicator_label6  "L5 (ALMA)"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrMediumSeaGreen
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

#property indicator_label7  "L6 (Kinematic)"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrOrange
#property indicator_style7  STYLE_DOT
#property indicator_width7  1

//--- 2. ตั้งค่าลูกศรสัญญาณไม้แรกตามเทรนด์ FIRST BUY / SELL (Plots 7-8)
#property indicator_label8  "Trend FIRST BUY"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrLime
#property indicator_width8  3

#property indicator_label9  "Trend FIRST SELL"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  clrRed
#property indicator_width9  3

//--- 3. ตั้งค่าลูกศรสัญญาณไม้ซ้ำตามเทรนด์ RE-ENTRY BUY / SELL (Plots 9-10)
#property indicator_label10 "Trend RE-BUY"
#property indicator_type10  DRAW_ARROW
#property indicator_color10 clrSpringGreen
#property indicator_width10 2

#property indicator_label11 "Trend RE-SELL"
#property indicator_type11  DRAW_ARROW
#property indicator_color11 clrTomato
#property indicator_width11 2

//--- 4. ตั้งค่าลูกศรสัญญาณไม้สวนเทรนด์ COUNTER BUY / SELL (Plots 11-12)
#property indicator_label12 "Counter BUY"
#property indicator_type12  DRAW_ARROW
#property indicator_color12 clrAqua
#property indicator_width12 2

#property indicator_label13 "Counter SELL"
#property indicator_type13  DRAW_ARROW
#property indicator_color13 clrOrange
#property indicator_width13 2

//--- 5. ตั้งค่าจุดแสดงตำแหน่ง SL เริ่มต้นของสัญญาณ (Plot 13)
#property indicator_label14 "Initial SL Level"
#property indicator_type14  DRAW_ARROW
#property indicator_color14 clrYellow
#property indicator_width14 2

//--- 6. Buffer แสดงค่า Z-Score ในหน้าต่าง Data Window (Plot 14)
#property indicator_label15 "Z-Score"
#property indicator_type15  DRAW_NONE

//====================================================================
// 🎛️ INPUT PARAMETERS (ตรงกับ EA v8.80 + ตั้งค่า Z ลอยบนแท่งปัจจุบัน)
//====================================================================
input group "=== 1. เงื่อนไขยิงไม้แรก & ระยะตัดขาดทุนเริ่มต้น (SL) ==="
input double   InpFirstZ_Trigger         = 1.00;      // ค่า |Z-Score| ขั้นต่ำสำหรับยิงไม้แรก (ด่านที่ 1)
input double   InpFirstOpenDist_Pts      = 10000.0;   // ระยะห่างจากราคาเปิดแท่งปัจจุบันเพื่อยิงไม้แรก (จุด - ด่านที่ 2)
input double   InpReEntryFixedSL_Pts     = 10000.0;   // ระยะ SL คงที่เริ่มต้นของไม้ซ้ำตามเทรนด์ (จุด)
input double   InpCounterFixedSL_Pts     = 10000.0;   // ระยะ SL คงที่เริ่มต้นของไม้สวนเทรนด์ (จุด)

input group "=== 2. ระบบ Z-Score (ไม้ซ้ำ & ไม้สวนเทรนด์ 2 ระดับ) ==="
input double   InpReEntryZ_Max           = 1.40;      // โซนค่า |Z| ปลุกเวลายิงไม้ซ้ำ (0 < |Z| < 1.4)
input int      InpReEntryWait_Sec        = 3;         // [แท่งสด] เวลาไม่ทำ High/Low ใหม่ (สวนทิศเทรนด์) ก่อนยิงไม้ซ้ำ (วินาที)
input double   InpCounterZ_Trigger       = 2.50;      // ค่า |Z| ดักสวนเทรนด์ปกติ (จับเวลา)
input int      InpCounterWait_Sec        = 2;         // [แท่งสด] เวลาไม่ทำ High/Low ใหม่ ก่อนยิงสวนปกติ (วินาที)
input double   InpCounterCrisisZ         = 3.00;      // ค่า |Z| จุดวิกฤต (แตะแล้วยิงสวนทันที ไม่ต้องจับเวลา!)

input group "=== 3. ตัวกรอง Sideway (เนื้อเทียน > 5,000) & ความชันไม้ซ้ำ ==="
input double   InpReEntryMinBody_Pts     = 5000.0;    // ขนาดเนื้อเทียนแท่งก่อนหน้าขั้นต่ำในทิศตามเทรนด์ (จุด - กรอง Sideway)
input double   InpSlopeRetainPct         = 50.0;      // ความชันแท่งล่าสุดต้องเหลือไม่ต่ำกว่ากี่ % ของแท่งก่อนหน้า
input double   InpMinSlopeMove_Pts       = 25.0;      // ระยะขยับขั้นต่ำต่อแท่งเพื่อยืนยันว่าเส้นไม่นอนนิ่ง (จุด)

input group "=== 4. โล่บังทุนไม้ตามเทรนด์ 3 ระดับ (จำลองการถือสล็อต) ==="
input double   InpShield1_Trigger_Pts    = 5000.0;    // [โล่ตามเทรนด์ 1] กำไรเริ่มกางโล่ชั้นที่ 1 (จุด)
input double   InpShield1_Lock_Pts       = 500.0;     // [โล่ตามเทรนด์ 1] ระยะล็อกกำไรชั้นที่ 1 (จุด)
input double   InpShield2_Trigger_Pts    = 10000.0;   // [โล่ตามเทรนด์ 2] กำไรเริ่มกางโล่ชั้นที่ 2 (จุด)
input double   InpShield2_Lock_Pts       = 2000.0;    // [โล่ตามเทรนด์ 2] ระยะล็อกกำไรชั้นที่ 2 (จุด)
input double   InpShield3_Trigger_Pts    = 20000.0;   // [โล่ตามเทรนด์ 3] กำไรเริ่มเปิดโล่ชั้นที่ 3 (จุด)
input double   InpShield3_MinLock_Pts    = 3000.0;    // [โล่ตามเทรนด์ 3] ระยะล็อกกำไรขั้นต่ำก่อนดึงไล่ตามเส้นหลัก (จุด)

input group "=== 5. โล่เฉพาะไม้สวนเทรนด์ & โหมดไล่จี้เมื่อ |Z| แตะ 1.0 ==="
input double   InpCntShield1_Trig_Pts    = 2000.0;    // [โล่ไม้สวน 1] กำไรเริ่มกางโล่ชั้นที่ 1 (จุด)
input double   InpCntShield1_Lock_Pts    = 500.0;     // [โล่ไม้สวน 1] ระยะล็อกกำไรชั้นที่ 1 (จุด)
input double   InpCntShield2_Trig_Pts    = 3000.0;    // [โล่ไม้สวน 2] กำไรเริ่มกางโล่ชั้นที่ 2 (จุด)
input double   InpCntShield2_Lock_Pts    = 1000.0;    // [โล่ไม้สวน 2] ระยะล็อกกำไรชั้นที่ 2 (จุด)
input double   InpCntShield3_Trig_Pts    = 5000.0;    // [โล่ไม้สวน 3] กำไรเริ่มกางโล่ชั้นที่ 3 (จุด)
input double   InpCntShield3_Lock_Pts    = 2000.0;    // [โล่ไม้สวน 3] ระยะล็อกกำไรชั้นที่ 3 (จุด)
input double   InpCounterChokeZ          = 1.00;      // ค่า |Z| ที่เริ่มดึงโล่ไม้สวนเข้ามาไล่จี้ราคา
input double   InpCounterChokeTrail_Pts  = 1000.0;    // ระยะห่างโล่ไล่จี้ราคาของไม้สวนเมื่อ |Z| <= 1.0 (จุด)

input group "=== 6. ตั้งค่าเส้น Indicator ทั้ง 7 เส้น & Z-Score ==="
input int      InpMain_Period            = 20;        // ความยาวเส้นหลัก (SMA) และ Z-Score
input int      InpFast_Period            = 10;        // ความยาวเส้นย่อย 1-5

input group "=== 7. การแสดงค่า Z ลอยตรงแท่งปัจจุบัน (ทั้งบนและล่าง) ==="
input bool     InpShowFloatingBarZ       = true;      // แสดงค่า Z ลอยเหนือหัวและใต้ฐานแท่งปัจจุบัน
input double   InpFloatingBarZ_OffsetPts = 220.0;     // ระยะห่างตัวเลข Z จากปลายไส้แท่งปัจจุบัน (จุด)
input int      InpFloatingBarZ_FontSize  = 10;        // ขนาดตัวอักษรค่า Z ที่ลอยบน-ล่างแท่งปัจจุบัน
input bool     InpShowFloatingZLevels    = true;      // แสดงป้ายโซนระดับ Z (+ และ -) ลอยขนาบข้างแท่งปัจจุบัน
input int      InpFloatingZLevel_Shift   = 2;         // ระยะเยื้องป้ายโซนระดับ Z ไปทางขวาของแท่งปัจจุบัน (แท่ง)
input bool     InpShowZLines             = true;      // แสดงเส้นแนวนอนระดับราคา Z-Score ทั้งฝั่งบนและล่าง

input group "=== 8. การแสดงผลสัญญาณย้อนหลัง & กระดานสถานะ ==="
input bool     InpAllowTrendTrades       = true;      // แสดงสัญญาณโหมดตามเทรนด์ (ไม้แรก & ไม้ซ้ำ)
input bool     InpAllowCounterTrades     = true;      // แสดงสัญญาณโหมดสวนเทรนด์ (Z-Score)
input bool     InpShowTextLabels         = true;      // แสดงป้ายข้อความ BUY/SELL บนกราฟ
input bool     InpShowZScoreOnChart      = true;      // แสดงค่า Z-Score ท้ายป้าย BUY/SELL บนกราฟ
input bool     InpShowDashboard          = true;      // แสดงกระดานสถานะมุมซ้ายบน
input double   InpArrowOffset_Pts        = 450.0;     // ระยะห่างลูกศรสัญญาณจากปลายไส้เทียน (จุด)
input int      InpMaxHistoryBars         = 5000;      // จำนวนแท่งย้อนหลังที่เริ่มจำลอง (นับตอนโหลด/รีเซ็ต แล้วจุดเริ่มจะคงที่)
input int      InpUIRefresh_Msc          = 500;       // ความถี่อัปเดตเส้น Z & Dashboard (ms)

//====================================================================
// 🔒 INTERNAL DEFINITIONS & BUFFERS
//====================================================================
#define SLOT_FIRST   0
#define SLOT_RE      1
#define SLOT_COUNTER 2

#define KIND_NONE       0
#define KIND_FIRST_BUY  1
#define KIND_FIRST_SELL 2
#define KIND_RE_BUY     3
#define KIND_RE_SELL    4
#define KIND_CNT_BUY    5
#define KIND_CNT_SELL   6

const string OBJ_PREFIX     = "7L_IND88_";
const string OBJ_LBL_PREFIX = "7L_IND88_LBL_";
const string OBJ_LIVE_LBL   = "7L_IND88_LIVE_LBL_";
const string OBJ_FLOAT_TOP  = "7L_IND88_FLOAT_Z_TOP";
const string OBJ_FLOAT_BOT  = "7L_IND88_FLOAT_Z_BOT";
const string LINE_MAIN      = "7L_IND88_HLINE_MAIN";
const string NO_SIGNAL      = "ยังไม่มีสัญญาณ";

struct SimSlot {
   bool   active;
   int    dir;         // 1 = BUY, -1 = SELL
   double open_price;
   double sl;
   int    stage;       // ระดับโล่บังทุน
   int    open_bar;    // ดัชนีแท่งเทียนที่เปิดไม้
   int    kind;        // KIND_*
};

// สถานะทั้งหมดของเครื่องจำลอง ณ แท่งที่คำนวณล่าสุด
struct SimState {
   int     cycle_dir;
   bool    first_fired;
   int     first_bar;
   bool    was_in[6];
   bool    returned[6];
   int     returned_count;
   SimSlot slots[3];
   // ผลประเมินของแท่งล่าสุด (ใช้แสดงบน Dashboard)
   bool    touched_main;
   double  body1_pts;
   bool    body_ok;
   bool    slope_ok;
   string  last_sig_name;
   double  last_sig_z;
};

double BufMain[], BufL1[], BufL2[], BufL3[], BufL4[], BufL5[], BufL6[];
double BufFirstBuy[], BufFirstSell[];
double BufReBuy[], BufReSell[];
double BufCounterBuy[], BufCounterSell[];
double BufSL[];
double BufZScore[];
double BufStd[];

double pMult      = 1.0;
int    g_min_bars = 0;
double g_alma_weights[];
double g_alma_weight_sum = 0.0;

// สถานะถาวร ณ แท่งปิดล่าสุดที่ยืนยันแล้ว
SimState g_state;
int      g_state_bar  = -1;
datetime g_state_time = 0;

// ติดตาม High/Low ของแท่งสด เพื่อจับเวลา No New High/Low
datetime g_bar0_time   = 0;
double   g_bar0_hi     = 0.0;
double   g_bar0_lo     = 0.0;
long     g_bar0_hi_msc = 0;
long     g_bar0_lo_msc = 0;

// ตัวแปรสถานะของแท่งปัจจุบันสำหรับแสดงผล Dashboard & เส้น Z-Score
int     g_live_cycle_dir          = 0;
bool    g_live_first_fired        = false;
int     g_live_returned_count     = 0;
bool    g_live_bar0_touched_main  = false;
double  g_live_bar1_body_pts      = 0.0;
bool    g_live_body_ok            = false;
bool    g_live_slope_ok           = false;
double  g_live_raw_z              = 0.0;
double  g_live_trend_z            = 0.0;
string  g_live_last_sig_name      = NO_SIGNAL;
double  g_live_last_sig_z         = 0.0;
SimSlot g_live_slots[3];

long    g_last_ui_update_msc      = 0;

double Pts(double points) { return points * pMult; }

long GetSimTimeMsc() {
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick) && tick.time_msc > 0) return (long)tick.time_msc;
   return (long)TimeCurrent() * 1000;
}

//====================================================================
// 🧰 SLOT & STATE HELPERS
//====================================================================
void ClearSimSlot(SimSlot &s) {
   s.active     = false;
   s.dir        = 0;
   s.open_price = 0.0;
   s.sl         = 0.0;
   s.stage      = 0;
   s.open_bar   = -1;
   s.kind       = KIND_NONE;
}

void OpenSlot(SimSlot &s, int kind, int dir, double open_price, double sl, int bar) {
   s.active     = true;
   s.dir        = dir;
   s.open_price = open_price;
   s.sl         = sl;
   s.stage      = 0;
   s.open_bar   = bar;
   s.kind       = kind;
}

// ขยับ SL ได้ทางเดียว: BUY ขึ้นอย่างเดียว / SELL ลงอย่างเดียว (sl = 0 คือยังไม่มี SL)
void RatchetSL(SimSlot &s, double new_sl) {
   new_sl = NormalizeDouble(new_sl, _Digits);
   if(s.dir == 1) {
      if(new_sl > s.sl) s.sl = new_sl;
   } else {
      if(s.sl == 0.0 || new_sl < s.sl) s.sl = new_sl;
   }
}

string KindName(int kind) {
   switch(kind) {
      case KIND_FIRST_BUY:  return "FIRST_BUY";
      case KIND_FIRST_SELL: return "FIRST_SELL";
      case KIND_RE_BUY:     return "RE_BUY";
      case KIND_RE_SELL:    return "RE_SELL";
      case KIND_CNT_BUY:    return "CNT_BUY";
      case KIND_CNT_SELL:   return "CNT_SELL";
   }
   return "-";
}

// ไม้ที่ถืออยู่เหนือเส้นหลัก (ตัดจบเมื่อ Low แตะ Main)
bool IsUpperZoneKind(int kind) {
   return (kind == KIND_FIRST_BUY || kind == KIND_RE_BUY || kind == KIND_CNT_SELL);
}

void ResetState(SimState &st) {
   st.cycle_dir   = 0;
   st.first_fired = false;
   st.first_bar   = -1;
   for(int k = 0; k < 6; k++) { st.was_in[k] = false; st.returned[k] = false; }
   st.returned_count = 0;
   for(int s = 0; s < 3; s++) ClearSimSlot(st.slots[s]);
   st.touched_main  = false;
   st.body1_pts     = 0.0;
   st.body_ok       = false;
   st.slope_ok      = false;
   st.last_sig_name = NO_SIGNAL;
   st.last_sig_z    = 0.0;
}

// เริ่มวัฏจักรใหม่ (dir = 0 คือจบเทรนด์) ล้างสล็อตทั้งหมด
void StartCycle(SimState &st, int dir) {
   for(int s = 0; s < 3; s++) ClearSimSlot(st.slots[s]);
   st.cycle_dir   = dir;
   st.first_fired = false;
   st.first_bar   = -1;
   for(int k = 0; k < 6; k++) { st.was_in[k] = (dir != 0); st.returned[k] = false; }
}

void ClearSignalsAt(int i) {
   BufFirstBuy[i]    = EMPTY_VALUE;
   BufFirstSell[i]   = EMPTY_VALUE;
   BufReBuy[i]       = EMPTY_VALUE;
   BufReSell[i]      = EMPTY_VALUE;
   BufCounterBuy[i]  = EMPTY_VALUE;
   BufCounterSell[i] = EMPTY_VALUE;
   BufSL[i]          = EMPTY_VALUE;
}

void DeleteLiveLabels() {
   ObjectDelete(0, OBJ_LIVE_LBL + "FIRST");
   ObjectDelete(0, OBJ_LIVE_LBL + "RE");
   ObjectDelete(0, OBJ_LIVE_LBL + "CNT");
}

void TrackBar0Extremes(datetime bar_time, double hi, double lo, long now_msc) {
   if(bar_time != g_bar0_time) {
      g_bar0_time   = bar_time;
      g_bar0_hi     = hi;
      g_bar0_lo     = lo;
      g_bar0_hi_msc = now_msc;
      g_bar0_lo_msc = now_msc;
      return;
   }
   if(hi > g_bar0_hi) { g_bar0_hi = hi; g_bar0_hi_msc = now_msc; }
   if(lo < g_bar0_lo) { g_bar0_lo = lo; g_bar0_lo_msc = now_msc; }
}

//====================================================================
// 🚀 INITIALIZATION
//====================================================================
void InitALMAWeights(int period) {
   ArrayResize(g_alma_weights, period);
   g_alma_weight_sum = 0.0;
   double offset = 0.85;
   double sigma  = 6.0;
   double m      = offset * (period - 1);
   double s      = period / sigma;

   for(int k = 0; k < period; k++) {
      double x = (period - 1 - k);
      double w = MathExp(-MathPow(x - m, 2) / (2.0 * s * s));
      g_alma_weights[k]  = w;
      g_alma_weight_sum += w;
   }
}

int OnInit() {
   if(InpMain_Period < 2 || InpFast_Period < 2) {
      Print("❌ InpMain_Period และ InpFast_Period ต้องมีค่าอย่างน้อย 2");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMaxHistoryBars < 10) {
      Print("❌ InpMaxHistoryBars ต้องมีค่าอย่างน้อย 10");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpReEntryWait_Sec < 0 || InpCounterWait_Sec < 0) {
      Print("❌ เวลาจับ No New High/Low ต้องไม่ติดลบ");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(_Digits == 2 || _Digits == 4) pMult = 0.1;
   else pMult = 1.0;

   int sqrt_p = (int)MathMax(1, MathFloor(MathSqrt(InpFast_Period)));
   g_min_bars = MathMax(InpMain_Period + 5, InpFast_Period + sqrt_p + 10);

   InitALMAWeights(InpFast_Period);

   // ผูก Buffers เส้นทั้ง 7
   SetIndexBuffer(0, BufMain, INDICATOR_DATA);
   SetIndexBuffer(1, BufL1,   INDICATOR_DATA);
   SetIndexBuffer(2, BufL2,   INDICATOR_DATA);
   SetIndexBuffer(3, BufL3,   INDICATOR_DATA);
   SetIndexBuffer(4, BufL4,   INDICATOR_DATA);
   SetIndexBuffer(5, BufL5,   INDICATOR_DATA);
   SetIndexBuffer(6, BufL6,   INDICATOR_DATA);

   // ผูก Buffers ลูกศรสัญญาณ + SL + Z-Score
   SetIndexBuffer(7,  BufFirstBuy,    INDICATOR_DATA);
   SetIndexBuffer(8,  BufFirstSell,   INDICATOR_DATA);
   SetIndexBuffer(9,  BufReBuy,       INDICATOR_DATA);
   SetIndexBuffer(10, BufReSell,      INDICATOR_DATA);
   SetIndexBuffer(11, BufCounterBuy,  INDICATOR_DATA);
   SetIndexBuffer(12, BufCounterSell, INDICATOR_DATA);
   SetIndexBuffer(13, BufSL,          INDICATOR_DATA);
   SetIndexBuffer(14, BufZScore,      INDICATOR_DATA);

   // Buffer คำนวณภายใน (ไม่วาด)
   SetIndexBuffer(15, BufStd,         INDICATOR_CALCULATIONS);

   // รหัสลูกศร Wingdings
   PlotIndexSetInteger(7,  PLOT_ARROW, 233); // ลูกศรขึ้นหนา (First Buy)
   PlotIndexSetInteger(8,  PLOT_ARROW, 234); // ลูกศรลงหนา (First Sell)
   PlotIndexSetInteger(9,  PLOT_ARROW, 241); // ลูกศรขึ้นโปร่ง (Re-Entry Buy)
   PlotIndexSetInteger(10, PLOT_ARROW, 242); // ลูกศรลงโปร่ง (Re-Entry Sell)
   PlotIndexSetInteger(11, PLOT_ARROW, 217); // ลูกศรสวนเทรนด์ขึ้น (Counter Buy)
   PlotIndexSetInteger(12, PLOT_ARROW, 218); // ลูกศรสวนเทรนด์ลง (Counter Sell)
   PlotIndexSetInteger(13, PLOT_ARROW, 159); // จุดกลม (Initial SL)

   for(int p = 0; p < 15; p++) {
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   }
   // ให้เส้นทั้ง 7 และ Z-Score เริ่มวาดพร้อมกัน
   for(int p = 0; p <= 6; p++) PlotIndexSetInteger(p, PLOT_DRAW_BEGIN, g_min_bars);
   PlotIndexSetInteger(14, PLOT_DRAW_BEGIN, g_min_bars);

   ResetState(g_state);
   g_state_bar  = -1;
   g_state_time = 0;
   g_bar0_time  = 0;
   for(int s = 0; s < 3; s++) ClearSimSlot(g_live_slots[s]);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME, "7-Lines Exhaustion v8.82 (Non-Repaint)");

   ObjectsDeleteAll(0, OBJ_PREFIX);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
}

//====================================================================
// 📐 7-LINES & Z-SCORE MATHEMATICAL ENGINE (Forward Indexing)
//====================================================================
double GetSMA_Fwd(const double &prices[], int index, int period) {
   double sum = 0.0;
   for(int k = 0; k < period; k++) sum += prices[index - k];
   return sum / period;
}

double GetStdDev_Fwd(const double &prices[], int index, double mean, int period) {
   if(period <= 1) return 0.0;
   double sum_sq = 0.0;
   for(int k = 0; k < period; k++) {
      double diff = prices[index - k] - mean;
      sum_sq += diff * diff;
   }
   return MathSqrt(sum_sq / period);
}

double GetWMA_Fwd(const double &prices[], int index, int period) {
   double sum = 0.0, weight = 0.0;
   for(int k = 0; k < period; k++) {
      double w = (double)(period - k);
      sum    += prices[index - k] * w;
      weight += w;
   }
   return (weight > 0.0) ? (sum / weight) : 0.0;
}

double GetInnerHMA_Fwd(const double &prices[], int index, int period) {
   int half_p  = (int)MathMax(1, MathFloor(period / 2.0));
   double wma1 = GetWMA_Fwd(prices, index, half_p);
   double wma2 = GetWMA_Fwd(prices, index, period);
   return (2.0 * wma1) - wma2;
}

double GetHMA_Fwd(const double &prices[], int index, int period) {
   int sqrt_p = (int)MathMax(1, MathFloor(MathSqrt(period)));
   double hma_sum = 0.0, hma_weight = 0.0;
   for(int k = 0; k < sqrt_p; k++) {
      double diff = GetInnerHMA_Fwd(prices, index - k, period);
      double w    = (double)(sqrt_p - k);
      hma_sum    += diff * w;
      hma_weight += w;
   }
   return (hma_weight > 0.0) ? (hma_sum / hma_weight) : prices[index];
}

double GetCG_LSMA_Fwd(const double &prices[], int index, int period) {
   if(period <= 1) return prices[index];
   double sum_x = 0.0, sum_y = 0.0, sum_xy = 0.0, sum_x2 = 0.0;
   for(int k = 0; k < period; k++) {
      double x = (double)(period - k);
      double y = prices[index - k];
      sum_x  += x;
      sum_y  += y;
      sum_xy += x * y;
      sum_x2 += x * x;
   }
   double denom = (period * sum_x2 - sum_x * sum_x);
   if(denom == 0.0) return prices[index];
   double m = (period * sum_xy - sum_x * sum_y) / denom;
   double b = (sum_y - m * sum_x) / period;
   return m * period + b;
}

double GetALMA_Fwd(const double &prices[], int index, int period) {
   if(g_alma_weight_sum <= 0.0) return prices[index];
   double sum = 0.0;
   for(int k = 0; k < period; k++) {
      sum += prices[index - k] * g_alma_weights[k];
   }
   return sum / g_alma_weight_sum;
}

double GetKinematic_Fwd(const double &prices[], int index) {
   double p0 = (prices[index]     + prices[index - 1] + prices[index - 2]) / 3.0;
   double p1 = (prices[index - 1] + prices[index - 2] + prices[index - 3]) / 3.0;
   double p2 = (prices[index - 2] + prices[index - 3] + prices[index - 4]) / 3.0;

   double velocity     = p0 - p1;
   double acceleration = velocity - (p1 - p2);

   return p0 + velocity + acceleration;
}

//====================================================================
// 🔍 ฟังก์ชันตรวจสอบความชัน 50% และทิศทางเส้นทั้ง 6
//====================================================================
bool CheckHistSlopeDown50Pct(double v3, double v2, double v1) {
   double min_move  = Pts(InpMinSlopeMove_Pts) * _Point;
   double ratio     = InpSlopeRetainPct / 100.0;
   double drop_prev = v3 - v2;
   double drop_last = v2 - v1;

   if(drop_prev < min_move || drop_last < min_move) return false;
   if(drop_last < drop_prev * ratio) return false;
   return true;
}

bool CheckHistSlopeUp50Pct(double v3, double v2, double v1) {
   double min_move  = Pts(InpMinSlopeMove_Pts) * _Point;
   double ratio     = InpSlopeRetainPct / 100.0;
   double rise_prev = v2 - v3;
   double rise_last = v1 - v2;

   if(rise_prev < min_move || rise_last < min_move) return false;
   if(rise_last < rise_prev * ratio) return false;
   return true;
}

bool AreAllSixBelowMain_At(int i) {
   double m = BufMain[i];
   return (BufL1[i] < m && BufL2[i] < m && BufL3[i] < m && BufL4[i] < m && BufL5[i] < m && BufL6[i] < m);
}

bool AreAllSixAboveMain_At(int i) {
   double m = BufMain[i];
   return (BufL1[i] > m && BufL2[i] > m && BufL3[i] > m && BufL4[i] > m && BufL5[i] > m && BufL6[i] > m);
}

//====================================================================
// 🛡️ จำลองการจัดการออเดอร์และการตัดจบของทั้ง 3 สล็อต
//====================================================================
void SimulateActiveSlotsOnBar(int i, SimSlot &slots[], double high_i, double low_i, double close_i,
                              double main_i, double main_prev, double close_prev, double stddev_i) {
   double s1_trig     = Pts(InpShield1_Trigger_Pts) * _Point;
   double s1_lock     = Pts(InpShield1_Lock_Pts)    * _Point;
   double s2_trig     = Pts(InpShield2_Trigger_Pts) * _Point;
   double s2_lock     = Pts(InpShield2_Lock_Pts)    * _Point;
   double s3_trig     = Pts(InpShield3_Trigger_Pts) * _Point;
   double s3_min_lock = Pts(InpShield3_MinLock_Pts) * _Point;

   double c1_trig     = Pts(InpCntShield1_Trig_Pts) * _Point;
   double c1_lock     = Pts(InpCntShield1_Lock_Pts) * _Point;
   double c2_trig     = Pts(InpCntShield2_Trig_Pts) * _Point;
   double c2_lock     = Pts(InpCntShield2_Lock_Pts) * _Point;
   double c3_trig     = Pts(InpCntShield3_Trig_Pts) * _Point;
   double c3_lock     = Pts(InpCntShield3_Lock_Pts) * _Point;
   double choke_dist  = Pts(InpCounterChokeTrail_Pts) * _Point;

   for(int s = 0; s < 3; s++) {
      if(!slots[s].active) continue;
      int dir = slots[s].dir;

      // 1. เช็คการตัดจบเมื่อราคากลับมาแตะเส้นหลัก Main[i]
      bool is_upper_zone = IsUpperZoneKind(slots[s].kind);
      if(is_upper_zone && low_i <= main_i) {
         ClearSimSlot(slots[s]);
         continue;
      }
      if(!is_upper_zone && high_i >= main_i) {
         ClearSimSlot(slots[s]);
         continue;
      }

      // 2. เช็คการชน SL ของสล็อต
      if(slots[s].sl > 0.0) {
         if(dir == 1 && low_i <= slots[s].sl) {
            ClearSimSlot(slots[s]);
            continue;
         }
         if(dir == -1 && high_i >= slots[s].sl) {
            ClearSimSlot(slots[s]);
            continue;
         }
      }

      double max_prof = (dir == 1) ? (high_i - slots[s].open_price) : (slots[s].open_price - low_i);

      // 3. อัปเดตโล่บังทุนของไม้ตามเทรนด์ (SLOT_FIRST & SLOT_RE)
      if(s == SLOT_FIRST || s == SLOT_RE) {
         if(s == SLOT_FIRST && i == slots[s].open_bar + 1) {
            bool in_profit = (dir == 1) ? (close_prev > slots[s].open_price) : (close_prev < slots[s].open_price);
            if(in_profit) RatchetSL(slots[s], main_prev);
         }

         if(slots[s].stage == 3 || max_prof >= s3_trig) {
            slots[s].stage = 3;
            double target_sl = (dir == 1) ? MathMax(slots[s].open_price + s3_min_lock, main_prev)
                                          : MathMin(slots[s].open_price - s3_min_lock, main_prev);
            RatchetSL(slots[s], target_sl);
         }
         else if(slots[s].stage < 2 && max_prof >= s2_trig) {
            slots[s].stage = 2;
            RatchetSL(slots[s], slots[s].open_price + dir * s2_lock);
         }
         else if(slots[s].stage < 1 && max_prof >= s1_trig) {
            slots[s].stage = 1;
            RatchetSL(slots[s], slots[s].open_price + dir * s1_lock);
         }
      }
      // 4. อัปเดตโล่บังทุน + โหมดไล่จี้ของไม้สวนเทรนด์ (SLOT_COUNTER)
      else if(s == SLOT_COUNTER && stddev_i > 0.0) {
         double best_cnt_z = (dir == 1) ? ((main_i - high_i) / stddev_i) : ((low_i - main_i) / stddev_i);

         if(slots[s].stage == 4 || best_cnt_z <= InpCounterChokeZ) {
            slots[s].stage = 4;
            double target_sl = close_i - dir * choke_dist;
            double lock      = 0.0;
            if(max_prof >= c3_trig)      lock = c3_lock;
            else if(max_prof >= c2_trig) lock = c2_lock;
            else if(max_prof >= c1_trig) lock = c1_lock;
            if(lock > 0.0) {
               double lock_sl = slots[s].open_price + dir * lock;
               target_sl = (dir == 1) ? MathMax(target_sl, lock_sl) : MathMin(target_sl, lock_sl);
            }
            RatchetSL(slots[s], target_sl);
         }
         else if(slots[s].stage < 3 && max_prof >= c3_trig) {
            slots[s].stage = 3;
            RatchetSL(slots[s], slots[s].open_price + dir * c3_lock);
         }
         else if(slots[s].stage < 2 && max_prof >= c2_trig) {
            slots[s].stage = 2;
            RatchetSL(slots[s], slots[s].open_price + dir * c2_lock);
         }
         else if(slots[s].stage < 1 && max_prof >= c1_trig) {
            slots[s].stage = 1;
            RatchetSL(slots[s], slots[s].open_price + dir * c1_lock);
         }
      }
   }
}

//====================================================================
// 🏷️ วาดป้ายข้อความจุดเข้า BUY/SELL พร้อมค่า Z-Score บนกราฟ
//====================================================================
void DrawSignalLabel(string name, datetime bar_time, double arrow_price, string sig_text,
                     double z_score, double entry_price, double sl_price, color clr, bool is_buy) {
   if(!InpShowTextLabels) return;

   string display_text = "  " + sig_text;
   if(InpShowZScoreOnChart) {
      display_text += StringFormat(" (Z: %+.2f)", z_score);
   }

   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TEXT, 0, bar_time, arrow_price);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, bar_time);
   ObjectSetDouble(0, name, OBJPROP_PRICE, arrow_price);
   ObjectSetString(0, name, OBJPROP_TEXT, display_text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, is_buy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   string sl_str = (sl_price > 0.0) ? DoubleToString(sl_price, _Digits) : "รอจบแท่งเทียน (ตัดเมื่อแตะ Main)";
   string tooltip = StringFormat("%s\nเวลา: %s\nZ-Score ณ จุดเข้า: %+.3f\nราคาเข้าประมาณการ: %s\nSL เริ่มต้น: %s",
                                 sig_text,
                                 TimeToString(bar_time, TIME_DATE|TIME_MINUTES),
                                 z_score,
                                 DoubleToString(entry_price, _Digits),
                                 sl_str);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

// เขียนลูกศร + จุด SL + ป้ายข้อความ และบันทึกสัญญาณล่าสุดลงสถานะ
void EmitSignal(SimState &st, double &arrow_buf[], int i, datetime bar_time, bool live,
                double arrow_price, double sl_mark, string tag, string sig_text,
                double z, double entry_price, double sl_label, color clr, bool is_buy) {
   arrow_buf[i] = arrow_price;
   BufSL[i]     = sl_mark;

   string name  = live ? (OBJ_LIVE_LBL + tag)
                       : (OBJ_LBL_PREFIX + tag + "_" + IntegerToString((long)bar_time));
   string shown = live ? (sig_text + " (สด)") : sig_text;
   DrawSignalLabel(name, bar_time, arrow_price, shown, z, entry_price, sl_label, clr, is_buy);

   st.last_sig_name = live ? (sig_text + " (แท่งสด - รอยืนยันเมื่อปิดแท่ง)") : sig_text;
   st.last_sig_z    = z;
}

//====================================================================
// ⚙️ เดินเครื่องจำลอง 1 แท่ง (live = true คือพรีวิวแท่งสดบนสำเนาสถานะ)
//====================================================================
void StepBar(SimState &st, int i, bool live, long now_msc,
             const datetime &time[], const double &open[], const double &high[],
             const double &low[], const double &close[]) {
   double m0   = BufMain[i], m1 = BufMain[i - 1], m2 = BufMain[i - 2], m3 = BufMain[i - 3];
   double std0 = BufStd[i];
   if(std0 <= 0.0) return;

   double first_open_dist = Pts(InpFirstOpenDist_Pts)  * _Point;
   double min_body_dist   = Pts(InpReEntryMinBody_Pts) * _Point;
   double re_sl_dist      = Pts(InpReEntryFixedSL_Pts) * _Point;
   double cnt_sl_dist     = Pts(InpCounterFixedSL_Pts) * _Point;
   double arrow_offset    = Pts(InpArrowOffset_Pts)    * _Point;

   // 1. ตรวจสอบการจบเทรนด์เมื่อเส้นทั้ง 6 กลับมาแตะเส้นหลักครบ 6 เส้น
   st.returned_count = 0;
   if(st.cycle_dir != 0) {
      double l_curr[6];
      l_curr[0] = BufL1[i]; l_curr[1] = BufL2[i]; l_curr[2] = BufL3[i];
      l_curr[3] = BufL4[i]; l_curr[4] = BufL5[i]; l_curr[5] = BufL6[i];

      for(int k = 0; k < 6; k++) {
         if(st.returned[k]) {
            st.returned_count++;
            continue;
         }
         bool in_trend = (st.cycle_dir == -1) ? (l_curr[k] < m0) : (l_curr[k] > m0);
         if(in_trend) st.was_in[k] = true;
         else if(st.was_in[k]) {
            st.returned[k] = true;
            st.returned_count++;
         }
      }

      if(st.returned_count >= 6) {
         StartCycle(st, 0);
         st.returned_count = 0;
      }
   }

   // 2. ตรวจสอบการสลับเทรนด์หรือเริ่มเทรนด์ใหม่ด้วยเส้นทั้ง 6 เทียบเส้นหลัก
   if(st.cycle_dir == -1 && AreAllSixAboveMain_At(i))     StartCycle(st, 1);
   else if(st.cycle_dir == 1 && AreAllSixBelowMain_At(i)) StartCycle(st, -1);
   else if(st.cycle_dir == 0) {
      if(AreAllSixBelowMain_At(i))      StartCycle(st, -1);
      else if(AreAllSixAboveMain_At(i)) StartCycle(st, 1);
   }

   // 3. จำลองการตัดจบเมื่อราคาแตะเส้นหลัก และการขยับโล่บังทุนของสล็อตที่ถืออยู่
   SimulateActiveSlotsOnBar(i, st.slots, high[i], low[i], close[i], m0, m1, close[i - 1], std0);

   // คำนวณค่า Z-Score ของแท่ง i
   double z_close_up   = (close[i] - m0) / std0;
   double z_close_down = (m0 - close[i]) / std0;
   double z_high_up    = (high[i]  - m0) / std0;
   double z_low_down   = (m0 - low[i])   / std0;

   bool bar_touched_main = (low[i] <= m0 && high[i] >= m0);
   st.touched_main = bar_touched_main;

   //------------------------------------------------------------------
   // 🚀 เฟสที่ 1: ยิงไม้แรกตามเทรนด์ (ระเบิดฉีกตัวจากเส้นหลัก - SLOT_FIRST)
   //------------------------------------------------------------------
   if(InpAllowTrendTrades && !st.first_fired && !st.slots[SLOT_FIRST].active) {
      bool cond_first_sell = (z_low_down > InpFirstZ_Trigger) && ((open[i] - low[i]) > first_open_dist) && bar_touched_main;
      bool cond_first_buy  = (z_high_up  > InpFirstZ_Trigger) && ((high[i] - open[i]) > first_open_dist) && bar_touched_main;

      if(cond_first_sell && st.cycle_dir <= 0) {
         if(st.cycle_dir == 0) StartCycle(st, -1);
         double trig_price = MathMin(open[i] - first_open_dist, m0 - InpFirstZ_Trigger * std0);
         double trig_z     = -MathMax(InpFirstZ_Trigger, z_close_down);

         EmitSignal(st, BufFirstSell, i, time[i], live, high[i] + arrow_offset, m0,
                    "FIRST", "FIRST SELL", trig_z, trig_price, m0, clrRed, false);
         OpenSlot(st.slots[SLOT_FIRST], KIND_FIRST_SELL, -1, trig_price, 0.0, i);
         st.first_fired = true;
         st.first_bar   = i;
      }
      else if(cond_first_buy && st.cycle_dir >= 0) {
         if(st.cycle_dir == 0) StartCycle(st, 1);
         double trig_price = MathMax(open[i] + first_open_dist, m0 + InpFirstZ_Trigger * std0);
         double trig_z     = MathMax(InpFirstZ_Trigger, z_close_up);

         EmitSignal(st, BufFirstBuy, i, time[i], live, low[i] - arrow_offset, m0,
                    "FIRST", "FIRST BUY", trig_z, trig_price, m0, clrLime, true);
         OpenSlot(st.slots[SLOT_FIRST], KIND_FIRST_BUY, 1, trig_price, 0.0, i);
         st.first_fired = true;
         st.first_bar   = i;
      }
   }

   //------------------------------------------------------------------
   // 🔍 ประเมินตัวกรอง Sideway เนื้อเทียน Bar[i-1] และความชัน 50%
   //------------------------------------------------------------------
   double body1_pts    = (close[i - 1] - open[i - 1]) / (_Point * pMult);
   bool   body_sell_ok = ((open[i - 1] - close[i - 1]) > min_body_dist);
   bool   body_buy_ok  = ((close[i - 1] - open[i - 1]) > min_body_dist);
   bool   re_body_ok   = (st.cycle_dir == -1) ? body_sell_ok : ((st.cycle_dir == 1) ? body_buy_ok : false);

   bool re_slope_ok = false;
   if(re_body_ok) {
      if(st.cycle_dir == -1) {
         re_slope_ok = (BufL3[i - 1] < m1) && (BufL4[i - 1] < m1) &&
                       CheckHistSlopeDown50Pct(m3, m2, m1) &&
                       CheckHistSlopeDown50Pct(BufL3[i - 3], BufL3[i - 2], BufL3[i - 1]) &&
                       CheckHistSlopeDown50Pct(BufL4[i - 3], BufL4[i - 2], BufL4[i - 1]) &&
                       (BufL3[i] < m0) && (BufL4[i] < m0);
      }
      else if(st.cycle_dir == 1) {
         re_slope_ok = (BufL3[i - 1] > m1) && (BufL4[i - 1] > m1) &&
                       CheckHistSlopeUp50Pct(m3, m2, m1) &&
                       CheckHistSlopeUp50Pct(BufL3[i - 3], BufL3[i - 2], BufL3[i - 1]) &&
                       CheckHistSlopeUp50Pct(BufL4[i - 3], BufL4[i - 2], BufL4[i - 1]) &&
                       (BufL3[i] > m0) && (BufL4[i] > m0);
      }
   }

   st.body1_pts = body1_pts;
   st.body_ok   = re_body_ok;
   st.slope_ok  = re_slope_ok;

   bool same_bar_as_first = (st.first_fired && i == st.first_bar);

   if(st.cycle_dir == 0) return;

   //---------------------------------------------------------------
   // 🔄 เฟสที่ 2: ไม้สวนเทรนด์ 2 ระดับ (ปกติ & วิกฤต - SLOT_COUNTER)
   //   แท่งสด: ระดับปกติต้องไม่ทำ Low/High ใหม่ครบ InpCounterWait_Sec / ระดับวิกฤตยิงทันที
   //---------------------------------------------------------------
   if(InpAllowCounterTrades && !same_bar_as_first && !st.slots[SLOT_COUNTER].active) {
      long cnt_wait_msc = (long)InpCounterWait_Sec * 1000;

      if(st.cycle_dir == -1 && z_low_down > InpCounterZ_Trigger) {
         bool is_crisis = (z_low_down >= InpCounterCrisisZ);
         bool ready     = !live || is_crisis || (now_msc - g_bar0_lo_msc >= cnt_wait_msc);
         if(ready) {
            double trig_z     = -z_low_down;
            double trig_price = low[i];
            double sl_price   = NormalizeDouble(trig_price - cnt_sl_dist, _Digits);
            string sig_lbl    = is_crisis ? "CRISIS BUY" : "CNT BUY";

            EmitSignal(st, BufCounterBuy, i, time[i], live, low[i] - arrow_offset, sl_price,
                       "CNT", sig_lbl, trig_z, trig_price, sl_price, clrAqua, true);
            OpenSlot(st.slots[SLOT_COUNTER], KIND_CNT_BUY, 1, trig_price, sl_price, i);
         }
      }
      else if(st.cycle_dir == 1 && z_high_up > InpCounterZ_Trigger) {
         bool is_crisis = (z_high_up >= InpCounterCrisisZ);
         bool ready     = !live || is_crisis || (now_msc - g_bar0_hi_msc >= cnt_wait_msc);
         if(ready) {
            double trig_z     = z_high_up;
            double trig_price = high[i];
            double sl_price   = NormalizeDouble(trig_price + cnt_sl_dist, _Digits);
            string sig_lbl    = is_crisis ? "CRISIS SELL" : "CNT SELL";

            EmitSignal(st, BufCounterSell, i, time[i], live, high[i] + arrow_offset, sl_price,
                       "CNT", sig_lbl, trig_z, trig_price, sl_price, clrOrange, false);
            OpenSlot(st.slots[SLOT_COUNTER], KIND_CNT_SELL, -1, trig_price, sl_price, i);
         }
      }
   }

   //---------------------------------------------------------------
   // 🎯 เฟสที่ 3: ไม้ซ้ำตามเทรนด์ (เนื้อเทียน + ความชัน 50% + 0 < |Z| < InpReEntryZ_Max)
   //   แท่งสด: SELL ต้องไม่ทำ High ใหม่ / BUY ต้องไม่ทำ Low ใหม่ ครบ InpReEntryWait_Sec
   //---------------------------------------------------------------
   bool trend_slot_free = (!st.first_fired) ? (!st.slots[SLOT_FIRST].active) : (!st.slots[SLOT_RE].active);
   if(!(InpAllowTrendTrades && re_body_ok && re_slope_ok && trend_slot_free)) return;

   if(live) {
      long last_ext_msc = (st.cycle_dir == -1) ? g_bar0_hi_msc : g_bar0_lo_msc;
      if(now_msc - last_ext_msc < (long)InpReEntryWait_Sec * 1000) return;
   }

   double trend_z_close = (st.cycle_dir == -1) ? z_close_down : z_close_up;
   double trend_z_open  = (st.cycle_dir == -1) ? ((m0 - open[i]) / std0) : ((open[i] - m0) / std0);

   bool in_wake_zone = ((trend_z_open  > 0.0 && trend_z_open  < InpReEntryZ_Max) ||
                        (trend_z_close > 0.0 && trend_z_close < InpReEntryZ_Max));

   if(!(in_wake_zone && trend_z_close > 0.0 && trend_z_close < InpCounterZ_Trigger)) return;

   double sig_z = (st.cycle_dir == -1) ? (-trend_z_close) : trend_z_close;

   if(!st.first_fired) {
      if(st.cycle_dir == -1) {
         EmitSignal(st, BufFirstSell, i, time[i], live, high[i] + arrow_offset, m0,
                    "FIRST", "FIRST SELL (RE)", sig_z, close[i], m0, clrRed, false);
         OpenSlot(st.slots[SLOT_FIRST], KIND_FIRST_SELL, -1, close[i], 0.0, i);
      } else {
         EmitSignal(st, BufFirstBuy, i, time[i], live, low[i] - arrow_offset, m0,
                    "FIRST", "FIRST BUY (RE)", sig_z, close[i], m0, clrLime, true);
         OpenSlot(st.slots[SLOT_FIRST], KIND_FIRST_BUY, 1, close[i], 0.0, i);
      }
      st.first_fired = true;
      st.first_bar   = i;
   }
   else {
      if(st.cycle_dir == -1) {
         double fixed_sl = NormalizeDouble(close[i] + re_sl_dist, _Digits);
         EmitSignal(st, BufReSell, i, time[i], live, high[i] + arrow_offset, fixed_sl,
                    "RE", "RE-SELL", sig_z, close[i], fixed_sl, clrTomato, false);
         OpenSlot(st.slots[SLOT_RE], KIND_RE_SELL, -1, close[i], fixed_sl, i);
      } else {
         double fixed_sl = NormalizeDouble(close[i] - re_sl_dist, _Digits);
         EmitSignal(st, BufReBuy, i, time[i], live, low[i] - arrow_offset, fixed_sl,
                    "RE", "RE-BUY", sig_z, close[i], fixed_sl, clrSpringGreen, true);
         OpenSlot(st.slots[SLOT_RE], KIND_RE_BUY, 1, close[i], fixed_sl, i);
      }
   }
}

//====================================================================
// 🎯 ฟังก์ชันเลือกสีตามความแรงของค่า Z-Score
//====================================================================
color GetZScoreZoneColor(double z_val) {
   double az = MathAbs(z_val);
   if(az >= InpCounterCrisisZ)  return clrMagenta;     // โซนวิกฤต
   if(az >= InpCounterZ_Trigger)return clrOrangeRed;   // โซนดักสวน
   if(az >= InpReEntryZ_Max)    return clrAqua;        // โซนพุ่งแรง
   if(az >= InpFirstZ_Trigger)  return clrLime;        // โซนฉีกตัวไม้แรก / ไม้ซ้ำ
   if(az > 0.05)                return clrSpringGreen; // โซนปลุกไม้ซ้ำ
   return clrGold;                                     // แตะเส้นหลัก Z ~ 0.00
}

//====================================================================
// ⚡ วาดค่า Z-Score ลอยอยู่ตรงแท่งเทียนปัจจุบัน ทั้งด้านบนและด้านล่าง
//====================================================================
void UpdateFloatingCurrentCandleZ(datetime bar0_time, double high0, double low0, double close0,
                                  double main0, double stddev0, bool has_top_sig, bool has_bot_sig) {
   if(!InpShowFloatingBarZ || stddev0 <= 0.0) {
      ObjectDelete(0, OBJ_FLOAT_TOP);
      ObjectDelete(0, OBJ_FLOAT_BOT);
      return;
   }

   double live_z = (close0 - main0) / stddev0;
   double high_z = (high0  - main0) / stddev0;
   double low_z  = (low0   - main0) / stddev0;

   // คำนวณระยะห่างจากหัวและท้ายแท่งปัจจุบัน (ขยับหลบอัตโนมัติหากแท่งปัจจุบันมีลูกศรสัญญาณ)
   double base_offset = Pts(InpFloatingBarZ_OffsetPts) * _Point;
   double sig_offset  = Pts(InpArrowOffset_Pts + 280.0) * _Point;

   double top_price = high0 + (has_top_sig ? MathMax(base_offset, sig_offset) : base_offset);
   double bot_price = low0  - (has_bot_sig ? MathMax(base_offset, sig_offset) : base_offset);

   string top_text = StringFormat("▲ Z: %+.2f (High Z: %+.2f)", live_z, high_z);
   string bot_text = StringFormat("▼ Z: %+.2f (Low Z: %+.2f)",  live_z, low_z);

   color top_clr = GetZScoreZoneColor(live_z >= 0.0 ? live_z : high_z);
   color bot_clr = GetZScoreZoneColor(live_z <= 0.0 ? live_z : low_z);

   // 1. ป้ายลอยด้านบนแท่งปัจจุบัน (Above High[0])
   if(ObjectFind(0, OBJ_FLOAT_TOP) < 0) {
      ObjectCreate(0, OBJ_FLOAT_TOP, OBJ_TEXT, 0, bar0_time, top_price);
   }
   ObjectSetInteger(0, OBJ_FLOAT_TOP, OBJPROP_TIME, bar0_time);
   ObjectSetDouble(0,  OBJ_FLOAT_TOP, OBJPROP_PRICE, top_price);
   ObjectSetString(0,  OBJ_FLOAT_TOP, OBJPROP_TEXT, top_text);
   ObjectSetInteger(0, OBJ_FLOAT_TOP, OBJPROP_COLOR, top_clr);
   ObjectSetInteger(0, OBJ_FLOAT_TOP, OBJPROP_FONTSIZE, InpFloatingBarZ_FontSize);
   ObjectSetString(0,  OBJ_FLOAT_TOP, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, OBJ_FLOAT_TOP, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   ObjectSetInteger(0, OBJ_FLOAT_TOP, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_FLOAT_TOP, OBJPROP_HIDDEN, true);

   // 2. ป้ายลอยด้านล่างแท่งปัจจุบัน (Below Low[0])
   if(ObjectFind(0, OBJ_FLOAT_BOT) < 0) {
      ObjectCreate(0, OBJ_FLOAT_BOT, OBJ_TEXT, 0, bar0_time, bot_price);
   }
   ObjectSetInteger(0, OBJ_FLOAT_BOT, OBJPROP_TIME, bar0_time);
   ObjectSetDouble(0,  OBJ_FLOAT_BOT, OBJPROP_PRICE, bot_price);
   ObjectSetString(0,  OBJ_FLOAT_BOT, OBJPROP_TEXT, bot_text);
   ObjectSetInteger(0, OBJ_FLOAT_BOT, OBJPROP_COLOR, bot_clr);
   ObjectSetInteger(0, OBJ_FLOAT_BOT, OBJPROP_FONTSIZE, InpFloatingBarZ_FontSize);
   ObjectSetString(0,  OBJ_FLOAT_BOT, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, OBJ_FLOAT_BOT, OBJPROP_ANCHOR, ANCHOR_TOP);
   ObjectSetInteger(0, OBJ_FLOAT_BOT, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_FLOAT_BOT, OBJPROP_HIDDEN, true);
}

//====================================================================
// 🎨 วาดเส้นแนวนอน + ป้ายระดับโซน Z ลอยขนาบแท่งปัจจุบัน ทั้งฝั่งบน (+Z) และล่าง (-Z)
//====================================================================
void DrawOrMoveHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string tooltip) {
   if(!InpShowZLines || price <= 0.0) {
      ObjectDelete(0, name);
      return;
   }
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   ObjectSetDouble(0,  name, OBJPROP_PRICE, NormalizeDouble(price, _Digits));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetString(0,  name, OBJPROP_TEXT, tooltip);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, tooltip);
}

void DrawOrMoveFloatingZTag(string name, datetime tag_time, double price, string text, color clr) {
   if(!InpShowFloatingZLevels || price <= 0.0) {
      ObjectDelete(0, name);
      return;
   }
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TEXT, 0, tag_time, price);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, tag_time);
   ObjectSetDouble(0,  name, OBJPROP_PRICE, NormalizeDouble(price, _Digits));
   ObjectSetString(0,  name, OBJPROP_TEXT, "  " + text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void UpdateZScoreChartLinesAndTags(datetime bar0_time, double main0, double stddev0) {
   if(stddev0 <= 0.0) return;

   int bar_sec = PeriodSeconds(PERIOD_CURRENT);
   if(bar_sec <= 0) bar_sec = 900;
   datetime tag_time = bar0_time + (datetime)(bar_sec * MathMax(1, InpFloatingZLevel_Shift));

   // คำนวณราคาของแต่ละระดับ Z ทั้งฝั่งบน (+Z เหนือเส้นหลัก) และฝั่งล่าง (-Z ใต้เส้นหลัก)
   double p_up_z10 = NormalizeDouble(main0 + (InpFirstZ_Trigger   * stddev0), _Digits);
   double p_up_z14 = NormalizeDouble(main0 + (InpReEntryZ_Max     * stddev0), _Digits);
   double p_up_z25 = NormalizeDouble(main0 + (InpCounterZ_Trigger * stddev0), _Digits);
   double p_up_z30 = NormalizeDouble(main0 + (InpCounterCrisisZ   * stddev0), _Digits);

   double p_dn_z10 = NormalizeDouble(main0 - (InpFirstZ_Trigger   * stddev0), _Digits);
   double p_dn_z14 = NormalizeDouble(main0 - (InpReEntryZ_Max     * stddev0), _Digits);
   double p_dn_z25 = NormalizeDouble(main0 - (InpCounterZ_Trigger * stddev0), _Digits);
   double p_dn_z30 = NormalizeDouble(main0 - (InpCounterCrisisZ   * stddev0), _Digits);

   // 1. เส้นหลัก Main SMA (Z = 0.00)
   DrawOrMoveHLine(LINE_MAIN, main0, clrGold, STYLE_DOT, 1,
                   "เส้นหลัก Main SMA(" + IntegerToString(InpMain_Period) + ") [Z = 0.00]: " + DoubleToString(main0, _Digits));
   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_Z0", tag_time, main0,
                          StringFormat("◀ Z: 0.00 (Main: %s)", DoubleToString(main0, _Digits)), clrGold);

   // 2. โซนฝั่งบน (+Z เหนือเส้นหลัก)
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_UP_Z10", p_up_z10, clrSilver, STYLE_DOT, 1,
                   StringFormat("โซนบน +Z %.2f (ไม้แรก BUY / ไล่จี้ไม้สวน): %s", InpFirstZ_Trigger, DoubleToString(p_up_z10, _Digits)));
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_UP_Z14", p_up_z14, clrAqua, STYLE_DOT, 1,
                   StringFormat("โซนบน +Z %.2f (ขอบปลุกไม้ซ้ำ BUY): %s", InpReEntryZ_Max, DoubleToString(p_up_z14, _Digits)));
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_UP_Z25", p_up_z25, clrOrangeRed, STYLE_DASH, 1,
                   StringFormat("โซนบน +Z %.2f (ดักสวน SELL %d วิ): %s", InpCounterZ_Trigger, InpCounterWait_Sec, DoubleToString(p_up_z25, _Digits)));
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_UP_Z30", p_up_z30, clrMagenta, STYLE_SOLID, 2,
                   StringFormat("🚨 โซนวิกฤตบน +Z %.2f (ยิงสวน SELL ทันที!): %s", InpCounterCrisisZ, DoubleToString(p_up_z30, _Digits)));

   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_UP_Z10", tag_time, p_up_z10,
                          StringFormat("◀ Z: +%.2f (%s)", InpFirstZ_Trigger, DoubleToString(p_up_z10, _Digits)), clrSilver);
   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_UP_Z14", tag_time, p_up_z14,
                          StringFormat("◀ Z: +%.2f [Re-Buy Max] (%s)", InpReEntryZ_Max, DoubleToString(p_up_z14, _Digits)), clrAqua);
   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_UP_Z25", tag_time, p_up_z25,
                          StringFormat("◀ Z: +%.2f [Cnt Sell] (%s)", InpCounterZ_Trigger, DoubleToString(p_up_z25, _Digits)), clrOrangeRed);
   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_UP_Z30", tag_time, p_up_z30,
                          StringFormat("◀ 🚨 Z: +%.2f [Crisis Sell] (%s)", InpCounterCrisisZ, DoubleToString(p_up_z30, _Digits)), clrMagenta);

   // 3. โซนฝั่งล่าง (-Z ใต้เส้นหลัก)
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_DN_Z10", p_dn_z10, clrSilver, STYLE_DOT, 1,
                   StringFormat("โซนล่าง -Z %.2f (ไม้แรก SELL / ไล่จี้ไม้สวน): %s", InpFirstZ_Trigger, DoubleToString(p_dn_z10, _Digits)));
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_DN_Z14", p_dn_z14, clrAqua, STYLE_DOT, 1,
                   StringFormat("โซนล่าง -Z %.2f (ขอบปลุกไม้ซ้ำ SELL): %s", InpReEntryZ_Max, DoubleToString(p_dn_z14, _Digits)));
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_DN_Z25", p_dn_z25, clrOrangeRed, STYLE_DASH, 1,
                   StringFormat("โซนล่าง -Z %.2f (ดักสวน BUY %d วิ): %s", InpCounterZ_Trigger, InpCounterWait_Sec, DoubleToString(p_dn_z25, _Digits)));
   DrawOrMoveHLine(OBJ_PREFIX + "HLINE_DN_Z30", p_dn_z30, clrMagenta, STYLE_SOLID, 2,
                   StringFormat("🚨 โซนวิกฤตล่าง -Z %.2f (ยิงสวน BUY ทันที!): %s", InpCounterCrisisZ, DoubleToString(p_dn_z30, _Digits)));

   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_DN_Z10", tag_time, p_dn_z10,
                          StringFormat("◀ Z: -%.2f (%s)", InpFirstZ_Trigger, DoubleToString(p_dn_z10, _Digits)), clrSilver);
   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_DN_Z14", tag_time, p_dn_z14,
                          StringFormat("◀ Z: -%.2f [Re-Sell Max] (%s)", InpReEntryZ_Max, DoubleToString(p_dn_z14, _Digits)), clrAqua);
   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_DN_Z25", tag_time, p_dn_z25,
                          StringFormat("◀ Z: -%.2f [Cnt Buy] (%s)", InpCounterZ_Trigger, DoubleToString(p_dn_z25, _Digits)), clrOrangeRed);
   DrawOrMoveFloatingZTag(OBJ_PREFIX + "TAG_DN_Z30", tag_time, p_dn_z30,
                          StringFormat("◀ 🚨 Z: -%.2f [Crisis Buy] (%s)", InpCounterCrisisZ, DoubleToString(p_dn_z30, _Digits)), clrMagenta);
}

//====================================================================
// 📋 DASHBOARD
//====================================================================
string FormatSimSlotSummary(const SimSlot &slot, bool is_counter) {
   if(!slot.active) return "ว่าง";
   string sh = "";
   if(!is_counter) {
      sh = StringFormat("รอโล่ 1 (%.0f)", InpShield1_Trigger_Pts);
      if(slot.stage == 1)      sh = StringFormat("🛡️ โล่ 1 (+%.0f)", InpShield1_Lock_Pts);
      else if(slot.stage == 2) sh = StringFormat("🛡️🛡️ โล่ 2 (+%.0f)", InpShield2_Lock_Pts);
      else if(slot.stage == 3) sh = StringFormat("🛡️🛡️🛡️ โล่ 3 (+%.0f/Main)", InpShield3_MinLock_Pts);
   } else {
      sh = StringFormat("รอโล่สวน 1 (%.0f)", InpCntShield1_Trig_Pts);
      if(slot.stage == 1)      sh = StringFormat("🛡️ โล่สวน 1 (+%.0f)", InpCntShield1_Lock_Pts);
      else if(slot.stage == 2) sh = StringFormat("🛡️🛡️ โล่สวน 2 (+%.0f)", InpCntShield2_Lock_Pts);
      else if(slot.stage == 3) sh = StringFormat("🛡️🛡️🛡️ โล่สวน 3 (+%.0f)", InpCntShield3_Lock_Pts);
      else if(slot.stage == 4) sh = StringFormat("🔥 ไล่จี้ %.0f จุด (|Z|<=%.2f)", InpCounterChokeTrail_Pts, InpCounterChokeZ);
   }
   string sl_str = (slot.sl > 0.0) ? DoubleToString(slot.sl, _Digits) : "-";
   return StringFormat("%s (%s | SL: %s)", KindName(slot.kind), sh, sl_str);
}

void RenderDashboard(double open0, double close0) {
   if(!InpShowDashboard) return;

   double open_dist_pts = 0.0;
   if(g_live_cycle_dir == -1)     open_dist_pts = (open0 - close0) / (_Point * pMult);
   else if(g_live_cycle_dir == 1) open_dist_pts = (close0 - open0) / (_Point * pMult);
   else                           open_dist_pts = MathAbs(close0 - open0) / (_Point * pMult);

   string dir_str   = "รอเส้นทั้ง 6 ลอยพ้นเส้นหลักครบทุกเส้น...";
   string z_map_str = "รอระบุทิศทางเทรนด์จากเส้นทั้ง 6 (+ หรือ -)";
   if(g_live_cycle_dir == -1) {
      dir_str   = "เทรนด์ขาลง [เส้นทั้ง 6 เป็น -] (SELL CYCLE)" + (g_live_first_fired ? " [มีไม้แรกแล้ว]" : " [ยังไม่มีไม้แรก]");
      z_map_str = StringFormat("ปลุกไม้ซ้ำ: -%.2f < Z < 0.00 | สวน %d วิ: -%.2f | วิกฤตยิงสด: -%.2f | ไล่จี้สวน: |Z|<=%.2f",
                               InpReEntryZ_Max, InpCounterWait_Sec, InpCounterZ_Trigger, InpCounterCrisisZ, InpCounterChokeZ);
   }
   else if(g_live_cycle_dir == 1) {
      dir_str   = "เทรนด์ขาขึ้น [เส้นทั้ง 6 เป็น +] (BUY CYCLE)" + (g_live_first_fired ? " [มีไม้แรกแล้ว]" : " [ยังไม่มีไม้แรก]");
      z_map_str = StringFormat("ปลุกไม้ซ้ำ: 0.00 < Z < +%.2f | สวน %d วิ: +%.2f | วิกฤตยิงสด: +%.2f | ไล่จี้สวน: |Z|<=%.2f",
                               InpReEntryZ_Max, InpCounterWait_Sec, InpCounterZ_Trigger, InpCounterCrisisZ, InpCounterChokeZ);
   }

   int act_count = (g_live_slots[0].active ? 1 : 0) + (g_live_slots[1].active ? 1 : 0) + (g_live_slots[2].active ? 1 : 0);
   string slot_first_str = FormatSimSlotSummary(g_live_slots[SLOT_FIRST], false);
   string slot_re_str    = FormatSimSlotSummary(g_live_slots[SLOT_RE], false);
   string slot_cnt_str   = FormatSimSlotSummary(g_live_slots[SLOT_COUNTER], true);

   string body_str = StringFormat("%+.0f จุด (%s)",
                                  g_live_bar1_body_pts,
                                  (g_live_body_ok ? StringFormat("✅ ผ่านเกณฑ์ > %.0f จุด", InpReEntryMinBody_Pts) : "🛑 ไม่ผ่าน/ข้ามแท่งนี้"));

   string last_sig_str = g_live_last_sig_name;
   if(g_live_last_sig_name != NO_SIGNAL) {
      last_sig_str += StringFormat(" | Z-Score ณ จุดเข้า = %+.2f", g_live_last_sig_z);
   }

   string diag_str = "✅ เงื่อนไขพร้อม";
   if(g_live_cycle_dir == 0) diag_str = "⏳ รอเส้นทั้ง 6 ลอยพ้นเส้นหลักครบทุกเส้น";
   else if(!g_live_body_ok)  diag_str = StringFormat("🛑 ติดกรอง Sideway ด่านแรก: เนื้อเทียน Bar[1] (%+.0f จุด) สั้นกว่า %.0f จุด", g_live_bar1_body_pts, InpReEntryMinBody_Pts);
   else if(!g_live_slope_ok) diag_str = StringFormat("⏸️ ติดเงื่อนไขความชัน: L3, L4 หรือ Main ดรอปเกิน %.0f%% (พักตัว L/U/V)", InpSlopeRetainPct);
   else if(g_live_trend_z <= 0.0 || g_live_trend_z >= InpReEntryZ_Max)
      diag_str = StringFormat("⏸️ รอราคาย่อเข้าโซนปลุกไม้ซ้ำ 0 < |Z| < %.2f (ปัจจุบัน |Z| = %.2f)", InpReEntryZ_Max, g_live_trend_z);

   string msg = "=== 📊 7-Lines Exhaustion Indicator v8.82 (Non-Repaint + Live Preview) ===\n";
   msg += "สถานะเทรนด์ (เส้นทั้ง 6) : " + dir_str + "\n";
   msg += "พิกัดล็อกค่า Z ตามเทรนด์ : " + z_map_str + "\n";
   msg += StringFormat("สล็อตจำลองที่ถืออยู่ (%d/3) : [ไม้แรก: %s] | [ไม้ซ้ำ: %s] | [ไม้สวน: %s]\n",
                       act_count, slot_first_str, slot_re_str, slot_cnt_str);
   msg += StringFormat("ค่า Z-Score ปัจจุบัน : %+.2f | ห่างจุดเปิดแท่ง: %.0f จุด | แท่งนี้เคยแตะเส้นหลัก: %s\n",
                       g_live_raw_z, open_dist_pts, (g_live_bar0_touched_main ? "✅ เคยแตะ" : "❌ ยังไม่แตะ"));
   msg += "ด่านกรอง Sideway เนื้อเทียน Bar[1] : " + body_str + " | ความชัน L3,L4,Main : " + (g_live_slope_ok ? "✅ ชันแรง" : "⏸️ ดรอป/พักตัว") + "\n";
   msg += "สัญญาณล่าสุดบนกราฟ : " + last_sig_str + "\n";
   msg += "สถานะดักไม้ซ้ำแท่งปัจจุบัน : " + diag_str + "\n";
   msg += "เส้นกลับไปแตะเส้นหลัก : " + IntegerToString(g_live_returned_count) + " / 6 เส้น (ราคาแตะเส้นหลัก=ตัดจบไม้ | ครบ 6 เส้น=จบเทรนด์)\n";
   msg += "หมายเหตุ: สัญญาณบนแท่งปัจจุบันเป็นพรีวิว (สด) จะยืนยันถาวรเมื่อปิดแท่ง";
   Comment(msg);
}

//====================================================================
// 📈 MAIN CALCULATION FUNCTION
//====================================================================
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) {

   ArraySetAsSeries(time,  false);
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   if(rates_total <= g_min_bars + 5) return(0);

   const int last    = rates_total - 1;
   long      now_msc = GetSimTimeMsc();

   // รีเซ็ตเมื่อโหลดครั้งแรก / ประวัติถูกโหลดเพิ่ม / ดัชนีแท่งเลื่อน (เช็คด้วยเวลาของแท่งที่ยืนยันล่าสุด)
   bool reset = (prev_calculated <= 0 || g_state_bar < 0 || g_state_bar >= last ||
                 time[g_state_bar] != g_state_time);

   //------------------------------------------------------------------
   // ขั้นตอนที่ 1: คำนวณเส้นทั้ง 7 + StdDev + Z-Score เฉพาะแท่งที่เปลี่ยน
   //------------------------------------------------------------------
   int calc_from = (reset || prev_calculated <= 0) ? 0 : (prev_calculated - 1);
   // ถ้า Terminal ขอคำนวณย้อนเข้าไปในช่วงที่ยืนยันแล้ว ให้รีเซ็ตทั้งหมดเพื่อไม่ให้สัญญาณถาวรหาย
   if(!reset && calc_from <= g_state_bar) {
      reset     = true;
      calc_from = 0;
   }
   double alpha = 2.0 / (InpFast_Period + 1.0);

   for(int i = calc_from; i < rates_total; i++) {
      ClearSignalsAt(i);

      if(i < g_min_bars) {
         BufMain[i]   = EMPTY_VALUE;
         BufL1[i]     = close[i];   // ค่าตั้งต้นของ EMA (ไม่ถูกวาดเพราะ PLOT_DRAW_BEGIN)
         BufL2[i]     = EMPTY_VALUE;
         BufL3[i]     = EMPTY_VALUE;
         BufL4[i]     = EMPTY_VALUE;
         BufL5[i]     = EMPTY_VALUE;
         BufL6[i]     = EMPTY_VALUE;
         BufZScore[i] = EMPTY_VALUE;
         BufStd[i]    = 0.0;
         continue;
      }

      BufMain[i] = GetSMA_Fwd(close, i, InpMain_Period);
      BufL1[i]   = close[i] * alpha + BufL1[i - 1] * (1.0 - alpha);
      BufL2[i]   = GetWMA_Fwd(close, i, InpFast_Period);
      BufL3[i]   = GetHMA_Fwd(close, i, InpFast_Period);
      BufL4[i]   = GetCG_LSMA_Fwd(close, i, InpFast_Period);
      BufL5[i]   = GetALMA_Fwd(close, i, InpFast_Period);
      BufL6[i]   = GetKinematic_Fwd(close, i);

      BufStd[i]    = GetStdDev_Fwd(close, i, BufMain[i], InpMain_Period);
      BufZScore[i] = (BufStd[i] > 0.0) ? NormalizeDouble((close[i] - BufMain[i]) / BufStd[i], 4) : 0.0;
   }

   //------------------------------------------------------------------
   // ขั้นตอนที่ 2: รีเซ็ตสถานะจำลอง (จุดเริ่มถูกล็อกไว้จนกว่าจะรีเซ็ตครั้งถัดไป)
   //------------------------------------------------------------------
   if(reset) {
      ObjectsDeleteAll(0, OBJ_LBL_PREFIX);
      ResetState(g_state);
      int start_bar = MathMax(g_min_bars + 4, rates_total - InpMaxHistoryBars);
      g_state_bar   = start_bar - 1;
      g_state_time  = time[g_state_bar];
   }

   //------------------------------------------------------------------
   // ขั้นตอนที่ 3: ยืนยันสัญญาณถาวรเฉพาะแท่งที่ปิดแล้ว (เดินต่อจากสถานะเดิม)
   //------------------------------------------------------------------
   bool committed_new = false;
   for(int i = g_state_bar + 1; i <= last - 1; i++) {
      StepBar(g_state, i, false, now_msc, time, open, high, low, close);
      committed_new = true;
   }
   if(committed_new) {
      g_state_bar  = last - 1;
      g_state_time = time[g_state_bar];
   }

   //------------------------------------------------------------------
   // ขั้นตอนที่ 4: พรีวิวแท่งสดบนสำเนาสถานะ (ไม่บันทึกลง g_state)
   //------------------------------------------------------------------
   TrackBar0Extremes(time[last], high[last], low[last], now_msc);
   DeleteLiveLabels();

   SimState pv;
   pv = g_state;
   StepBar(pv, last, true, now_msc, time, open, high, low, close);

   g_live_cycle_dir         = pv.cycle_dir;
   g_live_first_fired       = pv.first_fired;
   g_live_returned_count    = pv.returned_count;
   g_live_bar0_touched_main = pv.touched_main;
   g_live_bar1_body_pts     = pv.body1_pts;
   g_live_body_ok           = pv.body_ok;
   g_live_slope_ok          = pv.slope_ok;
   g_live_last_sig_name     = pv.last_sig_name;
   g_live_last_sig_z        = pv.last_sig_z;
   g_live_raw_z             = BufZScore[last];
   g_live_trend_z           = (pv.cycle_dir == -1) ? (-g_live_raw_z) : ((pv.cycle_dir == 1) ? g_live_raw_z : 0.0);
   for(int s = 0; s < 3; s++) g_live_slots[s] = pv.slots[s];

   //------------------------------------------------------------------
   // ขั้นตอนที่ 5: อัปเดตการแสดงผล
   //------------------------------------------------------------------
   bool has_top_sig = (BufFirstSell[last] != EMPTY_VALUE || BufReSell[last] != EMPTY_VALUE || BufCounterSell[last] != EMPTY_VALUE);
   bool has_bot_sig = (BufFirstBuy[last]  != EMPTY_VALUE || BufReBuy[last]  != EMPTY_VALUE || BufCounterBuy[last]  != EMPTY_VALUE);

   UpdateFloatingCurrentCandleZ(time[last], high[last], low[last], close[last], BufMain[last], BufStd[last], has_top_sig, has_bot_sig);

   bool force_ui = reset || committed_new || now_msc < g_last_ui_update_msc;
   if(force_ui || now_msc - g_last_ui_update_msc >= (long)InpUIRefresh_Msc) {
      g_last_ui_update_msc = now_msc;
      UpdateZScoreChartLinesAndTags(time[last], BufMain[last], BufStd[last]);
      RenderDashboard(open[last], close[last]);
   }

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
