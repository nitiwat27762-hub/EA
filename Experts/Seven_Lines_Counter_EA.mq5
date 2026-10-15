﻿//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Fast Mean-Reversion Z-Score EA for XAUUSD (Indicator v8.82)  |
//+------------------------------------------------------------------+
//
// 🆕 v3.00
//  • Z แบบเส้นถดถอย (Regression Z): เส้นกลาง = เส้นถดถอยเชิงเส้น 20 แท่ง (รวมแท่งปัจจุบัน)
//    ตัวหาร = StdDev ของส่วนเบี่ยงเบนรอบเส้นถดถอย (ไม่นับความชันเทรนด์เป็นความผันผวน)
//    + พื้นขั้นต่ำของตัวหาร = InpSigmaFloorMult × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง (กัน Z พุ่งตอนเทรนด์เรียบ)
//      (ไม่ใช้ StdDev แบบ SMA เป็นพื้น เพราะมันพองตามความชันเทรนด์ — จะกด Z กลับไปเหมือนเดิม)
//    → แก้ปัญหา SMA ชันแล้ว Z ไม่แตะ (Z แบบ SMA ในเทรนด์เส้นตรงตันที่ ≈ 1.65 เสมอ)
//  • ป้องกันข่าว: ตัวจับช็อก (ช่วงแกว่งแท่ง ≥ 3×ATR → งดถึง 30 นาทีหลังแท่งช็อกปิด)
//    + กรองความต่อเนื่อง (แท่งที่เพิ่งปิดค้างในโซนสุดขั้วฝั่งเดียวกัน → ไม่สวน)
//    + ปฏิทินข่าว USD ระดับ High (ตัวเลือก, ใช้ไม่ได้ใน Strategy Tester)
//
// 🎯 นิยามระบบ (v2.00)
//  สวนกลับค่าที่ผิดปกติ (Z ≥ +2.5 / Z ≤ −3.0) ที่ "ควรดีดกลับอย่างรวดเร็ว"
//  ถ้าไม่ดีดกลับภายในเวลาที่กำหนด = สมมติฐานผิด → ออกทันที
//
// 📋 ตรรกะการเข้าไม้ (แยก SELL / BUY)
//  ปลดไก ──(Z ถอยกลับเกิน ReArm)──► พร้อมยิง ──(Z แตะเกณฑ์)──► เฝ้าจุดสุดขั้ว
//  ──(Z ถอยจากจุดสุดขั้ว ≥ Pullback)──► ผ่านตัวกรอง ──► เปิดไม้ ──► ปลดไก
//  • ถ้าระหว่างเฝ้า Z ถอยลึกเกินระดับ ReArm → ยกเลิกการเฝ้า (กลับเป็นพร้อมยิง)
//  • เริ่ม EA ในสถานะปลดไก (ไม่เข้ากลางทางเมื่อ Z เกินเกณฑ์อยู่แล้ว)
//
// 📋 ตรรกะการจัดการไม้
//  • TP / SL คงที่ตั้งแต่เปิดไม้
//  • ภายใน QuickWindow วินาทีแรก ตรวจทุก 1 วินาที: กำไรถึงจุดเริ่มไล่จี้ → เปิดระบบไล่จี้ทันที
//  • ครบ QuickWindow แล้วระบบไล่จี้ยังไม่ทำงาน → ตัดจบ + งดเปิดไม้ใหม่ทั้งแท่ง (TF ของ Z)
//  • หลังเปิดระบบไล่จี้ ขยับโล่ทุก TrailInterval วินาที (ทางเดียว)
//  • ชน SL แบบขาดทุน → พักเข้าไม้ทั้งสองฝั่ง SLCooldown นาที
//  • ห้ามเข้า 1 ชม.แรกหลังตลาดเปิดสัปดาห์ / ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//
// ⚡ การประหยัด CPU
//  • Z: แคช Σy, Σxy, Σy² ของแท่งที่ปิดแล้ว + ATR คำนวณเฉพาะตอนขึ้นแท่งใหม่ (ต่อ Tick ไม่กี่บรรทัดคณิต)
//  • จัดการไม้ / Dashboard / เส้น ทำบน OnTimer 1 วินาที, ตรวจ SL ผ่าน OnTradeTransaction (ไม่ไล่ประวัติ)
//  • Dashboard เขียนเฉพาะเมื่อข้อความเปลี่ยน, ไม่วาดอะไรใน Tester แบบไม่เปิด Visual
//
#property copyright   "Commander's Quant System"
#property version     "3.00"
#property description "สวนกลับค่า Z ผิดปกติที่ควรดีดกลับเร็ว สำหรับ XAUUSD (บัญชี Hedging)"
#property tester_indicator "Seven_Lines_Exhaustion_Ind.ex5"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score & จุดเข้า ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpSellZ             = 2.50;       // เฝ้า SELL เมื่อ Z ≥ +ค่านี้ (สวนขาขึ้น)
input double          InpBuyZ              = 3.00;       // เฝ้า BUY เมื่อ Z ≤ −ค่านี้ (สวนขาลง)
input double          InpPullbackZ         = 0.20;       // ยิงเมื่อ Z ถอยจากจุดสุดขั้วอย่างน้อยเท่านี้ (0 = ยิงทันทีที่แตะ)
input double          InpReArmBuffer       = 0.50;       // ระยะ Z ที่ต้องถอยกลับก่อนยิงไม้ถัดไปฝั่งเดิม
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot คงที่ต่อไม้
input int             InpMaxPositions      = 5;          // จำนวนไม้สูงสุด (รวมทั้งสองฝั่ง)
input double          InpTP_Pts            = 20000.0;    // Take Profit (จุด)
input double          InpSL_Pts            = 10000.0;    // Stop Loss (จุด)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์

input group "=== 3. ไล่จี้กำไร ==="
input double          InpTrailStart_Pts    = 8000.0;     // เริ่มไล่จี้เมื่อกำไรถึง (จุด)
input double          InpTrailDist_Pts     = 6000.0;     // ระยะโล่ห่างจากราคา (จุด)
input int             InpTrailInterval_Sec = 5;          // ขยับโล่ทุกกี่วินาที (หลังเริ่มไล่จี้แล้ว)

input group "=== 4. กฎดีดกลับเร็ว ==="
input int             InpQuickWindow_Sec   = 60;         // ไม้ต้องเข้าระบบไล่จี้ภายในกี่วินาที ไม่งั้นตัดจบ (0 = ปิด)
input int             InpSLCooldown_Min    = 5;          // พักเข้าไม้ทั้งสองฝั่งหลังชน SL ขาดทุน (นาที, 0 = ปิด)

input group "=== 5. ป้องกันข่าว / แรงต่อเนื่อง ==="
input bool            InpUseShockFilter    = true;       // [ช็อก] งดเข้าเมื่อช่วงแกว่งแท่ง ≥ ATR × ตัวคูณ
input int             InpShockATR_Period   = 14;         // [ช็อก] จำนวนแท่งของ ATR
input double          InpShockATR_Mult     = 3.0;        // [ช็อก] ตัวคูณ ATR
input int             InpShockBlock_Min    = 30;         // [ช็อก] งดเข้าไม้ต่อกี่นาทีหลังแท่งช็อกปิด
input bool            InpUsePersistFilter  = true;       // [ต่อเนื่อง] ไม่สวนถ้าแท่งที่เพิ่งปิดค้างในโซนสุดขั้วฝั่งเดียวกัน
input double          InpPersistZ          = 2.0;        // [ต่อเนื่อง] |Z ตอนปิดแท่ง| ที่ถือว่าค้างโซนสุดขั้ว
input bool            InpUseNewsCalendar   = false;      // [ข่าว] งดเข้ารอบข่าวระดับ High (ใช้ไม่ได้ใน Tester)
input string          InpNewsCurrency      = "USD";      // [ข่าว] สกุลเงินของข่าว
input int             InpNewsBefore_Min    = 15;         // [ข่าว] งดก่อนข่าวกี่นาที
input int             InpNewsAfter_Min     = 30;         // [ข่าว] งดหลังข่าวกี่นาที

input group "=== 6. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)

input group "=== 7. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowZLines        = true;       // แสดงเส้น Main / ระดับ SELL / ระดับ BUY
input bool            InpShow7Lines        = true;       // แนบ Indicator 7 เส้น (ต้องมี Seven_Lines_Exhaustion_Ind.ex5)
input int             InpFastPeriod        = 10;         // Fast Period ของ Indicator 7 เส้น

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define TS_OPEN       0
#define TS_WAIT_OPEN  1
#define TS_CLOSING    2
#define TS_CLOSED     3

const string OBJ_PREFIX     = "7LCEA_";
const string LINE_MAIN      = "7LCEA_MAIN";
const string LINE_SELL      = "7LCEA_SELL_Z";
const string LINE_BUY       = "7LCEA_BUY_Z";
const string IND_NAME       = "Seven_Lines_Exhaustion_Ind";
const string IND_SHORTNAME  = "7-Lines Exhaustion v8.82 (Non-Repaint)";
const long   WEEK_SEC       = 604800;
const long   DAY_SEC        = 86400;
const long   MERGE_GAP_SEC  = 12 * 3600;   // ช่องว่าง session สั้นกว่านี้ (เช่นพักรายวัน) ถือว่าตลาดยังเปิด

struct WeekBlock {
   long s;   // วินาทีนับจากวันอาทิตย์ 00:00 (เวลาเซิร์ฟเวอร์)
   long e;
};

// สถานะไกยิงของแต่ละฝั่ง
struct SideState {
   bool   armed;      // Z ถอยกลับมาแล้ว พร้อมเฝ้ารอบใหม่
   bool   watching;   // Z แตะเกณฑ์แล้ว กำลังเฝ้าจุดสุดขั้ว
   double extreme;    // Z สุดขั้วระหว่างเฝ้า (SELL = สูงสุด / BUY = ต่ำสุด)
};

CTrade    trade;
double    g_pmult        = 1.0;
bool      g_draw         = true;

// --- Z engine (แคชผลรวมของแท่งที่ปิดแล้ว, ค่าเลื่อนจุดอ้างอิง g_ref) ---
datetime  g_zbar_time    = 0;
bool      g_z_ready      = false;
double    g_ref          = 0.0;
double    g_sumY         = 0.0;   // Σy  ของแท่งปิด (x = 0..n-2)
double    g_sumXY        = 0.0;   // Σxy
double    g_sumYY        = 0.0;   // Σy²
double    g_sumD         = 0.0;   // Σd  ของส่วนต่างราคาปิดต่อแท่ง (ระหว่างแท่งปิด)
double    g_sumDD        = 0.0;   // Σd²
double    g_last_close   = 0.0;   // ราคาปิดแท่งล่าสุด (ใช้หาส่วนต่างของแท่งปัจจุบัน)
bool      g_z_valid      = false;
double    g_z            = 0.0;   // Regression Z (ใช้ตัดสินใจ)
double    g_center       = 0.0;   // ราคาเส้นกลาง (เส้นถดถอยที่แท่งปัจจุบัน)
double    g_sigma        = 0.0;   // ตัวหารที่ใช้จริง
bool      g_sigma_floor  = false; // ตัวหารถูกยกขึ้นเป็นพื้นขั้นต่ำ
double    g_z_sma        = 0.0;   // Z แบบ SMA เดิม (แสดงเทียบ)
double    g_prev_close_z = 0.0;   // Regression Z ของแท่งที่เพิ่งปิด (กรองความต่อเนื่อง)

// --- ตัวจับช็อก / ข่าว ---
double    g_atr          = 0.0;
double    g_bar0_hi      = 0.0;
double    g_bar0_lo      = 0.0;
datetime  g_shock_until  = 0;
datetime  g_news_times[];
string    g_news_names[];
datetime  g_news_loaded  = 0;

// --- ไกยิง & ตัวกั้น ---
SideState g_sell;
SideState g_buy;
datetime  g_next_try       = 0;
datetime  g_cooldown_until = 0;   // พักหลังชน SL ขาดทุน
datetime  g_block_bar      = 0;   // แท่ง (เวลาเปิดแท่ง) ที่งดเปิดไม้เพราะตัดจบตามเวลา
string    g_last_status    = "เริ่มทำงาน";
ulong     g_activated[];          // ไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว

// --- Session ---
WeekBlock g_blocks[];
int       g_block_count  = 0;
bool      g_always_open  = false;
bool      g_session_ok   = false;
datetime  g_blk_open     = 0;
datetime  g_blk_close    = 0;
bool      g_blk_valid    = false;

// --- UI ---
datetime  g_last_trail   = 0;
string    g_last_comment = "";
double    g_line_main    = 0.0;
double    g_line_sell    = 0.0;
double    g_line_buy     = 0.0;
int       g_ind_handle   = INVALID_HANDLE;

//====================================================================
// 🧰 HELPERS
//====================================================================
double PtsToPrice(double pts) { return pts * g_pmult * _Point; }
double PriceToPts(double px)  { return px / (g_pmult * _Point); }
double ND(double price)       { return NormalizeDouble(price, _Digits); }

datetime ServerNow() {
   datetime t = TimeTradeServer();
   if(t <= 0) t = TimeCurrent();
   return t;
}

datetime CurrentZBarTime() {
   return iTime(_Symbol, InpZ_Timeframe, 0);
}

double NormalizeLot(double lot) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   lot = MathFloor(lot / step + 1e-9) * step;
   lot = MathMax(vmin, MathMin(vmax, lot));
   int digits = (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(lot, digits);
}

string FormatDuration(long sec) {
   if(sec < 0) sec = 0;
   int d = (int)(sec / DAY_SEC);
   int h = (int)((sec % DAY_SEC) / 3600);
   int m = (int)((sec % 3600) / 60);
   int s = (int)(sec % 60);
   if(d > 0) return StringFormat("%dวัน %dชม. %02dน.", d, h, m);
   if(h > 0) return StringFormat("%dชม. %02dน.", h, m);
   return StringFormat("%dน. %02dว.", m, s);
}

bool IsOurPosition() {
   return (PositionGetInteger(POSITION_MAGIC) == InpMagic &&
           PositionGetString(POSITION_SYMBOL) == _Symbol);
}

void CountPositions(int &buys, int &sells) {
   buys = 0; sells = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) buys++;
      else sells++;
   }
}

//--- รายการไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว ---
bool IsActivated(ulong ticket) {
   for(int i = ArraySize(g_activated) - 1; i >= 0; i--)
      if(g_activated[i] == ticket) return true;
   return false;
}

void MarkActivated(ulong ticket) {
   if(IsActivated(ticket)) return;
   int n = ArraySize(g_activated);
   ArrayResize(g_activated, n + 1);
   g_activated[n] = ticket;
}

void PruneActivated() {
   int n = ArraySize(g_activated), w = 0;
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(g_activated[i])) g_activated[w++] = g_activated[i];
   if(w != n) ArrayResize(g_activated, w);
}

//====================================================================
// 📐 Z-SCORE ENGINE (Regression Z)
//   x = 0..n-1 (แท่งปัจจุบัน x = n-1), y = ราคาปิด − g_ref
//   เส้นถดถอย y = a + b·x, ส่วนเบี่ยงเบน SSR = Σy² − aΣy − bΣxy
//   Z_reg = (y_ปัจจุบัน − เส้นถดถอยที่ x=n-1) / max(σ_residual, FloorMult × σ_ส่วนต่างต่อแท่ง)
//   แท่งปิดถูกแคชเป็น Σy, Σxy, Σy², Σd, Σd² → ต่อ Tick คำนวณ O(1)
//====================================================================
bool ComputeZ(double sy, double sxy, double syy, double y_last, double sd, double sdd,
              double &z_reg, double &z_sma, double &fit, double &sigma, bool &floored) {
   double n   = (double)InpZ_Period;
   double sx  = n * (n - 1.0) / 2.0;
   double sxx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;

   double mean   = sy / n;
   double var_sm = syy / n - mean * mean;
   if(var_sm <= 0.0) return false;
   double sd_sma = MathSqrt(var_sm);

   double denom = n * sxx - sx * sx;
   double b     = (n * sxy - sx * sy) / denom;
   double a     = (sy - b * sx) / n;
   fit          = a + b * (n - 1.0);

   double ssr = syy - a * sy - b * sxy;
   if(ssr < 0.0) ssr = 0.0;
   double sd_res = MathSqrt(ssr / n);

   // StdDev ของส่วนต่างราคาต่อแท่ง (n-1 ค่า) — สเกลความผันผวนที่ไม่พองตามความชันเทรนด์
   double m      = n - 1.0;
   double md     = sd / m;
   double var_d  = sdd / m - md * md;
   double sd_min = (var_d > 0.0) ? MathSqrt(var_d) * InpSigmaFloorMult : 0.0;

   floored = (sd_res < sd_min);
   sigma   = floored ? sd_min : sd_res;
   if(sigma <= 0.0) return false;

   z_reg = (y_last - fit)  / sigma;
   z_sma = (y_last - mean) / sd_sma;
   return true;
}

// ATR ของแท่ง 2..P+1 (ไม่รวมแท่งที่เพิ่งปิด เพื่อไม่ให้แท่งช็อกดันฐานตัวเอง) + เช็คแท่งที่เพิ่งปิดเป็นแท่งช็อกไหม
void UpdateAtrAndPrevShock(datetime bar0_time) {
   g_atr = 0.0;
   if(!InpUseShockFilter) return;
   int    p   = InpShockATR_Period;
   int    cnt = p + 2;
   double h[], l[], c[];
   if(CopyHigh (_Symbol, InpZ_Timeframe, 1, cnt, h) != cnt ||
      CopyLow  (_Symbol, InpZ_Timeframe, 1, cnt, l) != cnt ||
      CopyClose(_Symbol, InpZ_Timeframe, 1, cnt, c) != cnt) return;

   double sum = 0.0;
   for(int k = 1; k <= p; k++)
      sum += MathMax(h[k], c[k - 1]) - MathMin(l[k], c[k - 1]);
   g_atr = sum / p;

   double range1 = h[cnt - 1] - l[cnt - 1];
   if(g_atr > 0.0 && range1 >= InpShockATR_Mult * g_atr) {
      datetime until = bar0_time + (datetime)(InpShockBlock_Min * 60);
      if(until > g_shock_until) {
         g_shock_until = until;
         PrintFormat("⚡ แท่งที่เพิ่งปิดเป็นแท่งช็อก (ช่วงแกว่ง %.0f จุด = %.1f×ATR) → งดเข้าไม้ถึง %s",
                     PriceToPts(range1), range1 / g_atr, TimeToString(until, TIME_MINUTES));
      }
   }
}

bool RefreshClosedBars() {
   datetime t0 = CurrentZBarTime();
   if(t0 == 0) return false;
   if(g_z_ready && t0 == g_zbar_time) return true;

   int    n = InpZ_Period;
   double c[];
   if(CopyClose(_Symbol, InpZ_Timeframe, 1, n, c) != n) {
      g_z_ready = false;
      return false;
   }
   g_ref = c[n - 1];

   // 1. Regression Z ของแท่งที่เพิ่งปิด (n แท่งปิด, แท่งล่าสุดอยู่ x = n-1)
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n; k++) {
      double y = c[k] - g_ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[k] - c[k - 1]; sd += d; sdd += d * d; }
   }
   double zr, zs, fit, sig;
   bool   fl;
   g_prev_close_z = ComputeZ(sy, sxy, syy, 0.0, sd, sdd, zr, zs, fit, sig, fl) ? zr : 0.0;

   // 2. แคชแท่งปิด n-1 แท่งล่าสุดสำหรับคำนวณสด (x = 0..n-2) + ส่วนต่างระหว่างแท่งปิด (n-2 ค่า)
   g_sumY = 0.0; g_sumXY = 0.0; g_sumYY = 0.0; g_sumD = 0.0; g_sumDD = 0.0;
   for(int k = 1; k < n; k++) {
      double y = c[k] - g_ref;
      int    x = k - 1;
      g_sumY += y; g_sumXY += x * y; g_sumYY += y * y;
      if(k > 1) { double d = c[k] - c[k - 1]; g_sumD += d; g_sumDD += d * d; }
   }
   g_last_close = c[n - 1];

   // 3. ATR / แท่งช็อก / ช่วงแกว่งของแท่งปัจจุบัน
   UpdateAtrAndPrevShock(t0);
   g_bar0_hi = iHigh(_Symbol, InpZ_Timeframe, 0);
   g_bar0_lo = iLow (_Symbol, InpZ_Timeframe, 0);

   g_zbar_time = t0;
   g_z_ready   = true;
   return true;
}

bool UpdateZ(double bid) {
   g_z_valid = false;
   if(!RefreshClosedBars()) return false;

   if(bid > g_bar0_hi)                    g_bar0_hi = bid;
   if(g_bar0_lo <= 0.0 || bid < g_bar0_lo) g_bar0_lo = bid;

   double n   = (double)InpZ_Period;
   double y   = bid - g_ref;
   double sy  = g_sumY  + y;
   double sxy = g_sumXY + (n - 1.0) * y;
   double syy = g_sumYY + y * y;
   double d0  = bid - g_last_close;
   double sd  = g_sumD  + d0;
   double sdd = g_sumDD + d0 * d0;

   double zr, zs, fit, sig;
   bool   fl;
   if(!ComputeZ(sy, sxy, syy, y, sd, sdd, zr, zs, fit, sig, fl)) return false;

   g_z           = zr;
   g_z_sma       = zs;
   g_center      = g_ref + fit;
   g_sigma       = sig;
   g_sigma_floor = fl;
   g_z_valid     = true;
   return true;
}

// ตัวจับช็อกระหว่างแท่ง: ช่วงแกว่งแท่งปัจจุบัน ≥ ATR × ตัวคูณ → งดถึง X นาทีหลังแท่งนี้ปิด
void CheckShockLive() {
   if(!InpUseShockFilter || g_atr <= 0.0) return;
   double range0 = g_bar0_hi - g_bar0_lo;
   if(range0 < InpShockATR_Mult * g_atr) return;
   datetime until = g_zbar_time + (datetime)PeriodSeconds(InpZ_Timeframe) + (datetime)(InpShockBlock_Min * 60);
   if(until > g_shock_until) {
      g_shock_until = until;
      PrintFormat("⚡ แท่งปัจจุบันเป็นแท่งช็อก (ช่วงแกว่ง %.0f จุด = %.1f×ATR) → งดเข้าไม้ถึง %s",
                  PriceToPts(range0), range0 / g_atr, TimeToString(until, TIME_MINUTES));
   }
}

bool PersistBlocked(int dir) {
   if(!InpUsePersistFilter) return false;
   return (dir == -1) ? (g_prev_close_z >= InpPersistZ) : (g_prev_close_z <= -InpPersistZ);
}

//====================================================================
// 📰 ปฏิทินข่าว (โหลดทุก 10 นาที, ใช้เวลาเซิร์ฟเวอร์)
//====================================================================
bool NewsEnabled() {
   return InpUseNewsCalendar && !MQLInfoInteger(MQL_TESTER);
}

void RefreshNews(datetime now) {
   if(!NewsEnabled()) return;
   if(g_news_loaded != 0 && now - g_news_loaded < 600) return;
   g_news_loaded = now;

   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, now - (datetime)(InpNewsAfter_Min * 60), now + (datetime)DAY_SEC, NULL, InpNewsCurrency)) {
      PrintFormat("⚠️ โหลดปฏิทินข่าวไม่สำเร็จ (error %d)", GetLastError());
      return;
   }
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   for(int i = 0; i < ArraySize(vals); i++) {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      int n = ArraySize(g_news_times);
      ArrayResize(g_news_times, n + 1);
      ArrayResize(g_news_names, n + 1);
      g_news_times[n] = vals[i].time;
      g_news_names[n] = ev.name;
   }
}

bool InNewsWindow(datetime now, string &name) {
   if(!NewsEnabled()) return false;
   for(int i = 0; i < ArraySize(g_news_times); i++) {
      datetime t = g_news_times[i];
      if(now >= t - (datetime)(InpNewsBefore_Min * 60) && now <= t + (datetime)(InpNewsAfter_Min * 60)) {
         name = g_news_names[i];
         return true;
      }
   }
   return false;
}

string NextNewsText(datetime now) {
   if(!InpUseNewsCalendar) return "";
   if(!NewsEnabled())      return "📰 ปฏิทินข่าวใช้ไม่ได้ใน Tester";
   string name;
   if(InNewsWindow(now, name)) return "📰 ช่วงข่าว: " + name;
   datetime best = 0;
   string   best_name = "";
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] > now && (best == 0 || g_news_times[i] < best)) { best = g_news_times[i]; best_name = g_news_names[i]; }
   if(best == 0) return "📰 ไม่มีข่าว High ใน 24 ชม.";
   return StringFormat("📰 ข่าวถัดไป %s (อีก %s)", best_name, FormatDuration((long)(best - now)));
}

//====================================================================
// 🎯 SIGNAL STATE MACHINE (ไกยิง → เฝ้าจุดสุดขั้ว → ยิงเมื่อถอย)
//====================================================================
void ResetSide(SideState &s) {
   s.armed    = false;
   s.watching = false;
   s.extreme  = 0.0;
}

void UpdateSides() {
   //--- SELL: เฝ้า Z สูงสุด ---
   double sell_rearm = InpSellZ - InpReArmBuffer;
   if(g_sell.watching && g_z < sell_rearm) g_sell.watching = false;        // ถอยลึกเกิน → ยกเลิกเฝ้า
   if(!g_sell.armed && g_z < sell_rearm)   g_sell.armed    = true;
   if(g_sell.armed && !g_sell.watching && g_z >= InpSellZ) {
      g_sell.watching = true;
      g_sell.extreme  = g_z;
   }
   if(g_sell.watching && g_z > g_sell.extreme) g_sell.extreme = g_z;

   //--- BUY: เฝ้า Z ต่ำสุด ---
   double buy_rearm = -InpBuyZ + InpReArmBuffer;
   if(g_buy.watching && g_z > buy_rearm) g_buy.watching = false;
   if(!g_buy.armed && g_z > buy_rearm)   g_buy.armed    = true;
   if(g_buy.armed && !g_buy.watching && g_z <= -InpBuyZ) {
      g_buy.watching = true;
      g_buy.extreme  = g_z;
   }
   if(g_buy.watching && g_z < g_buy.extreme) g_buy.extreme = g_z;
}

bool SellTriggered() { return g_sell.watching && g_z <= g_sell.extreme - InpPullbackZ; }
bool BuyTriggered()  { return g_buy.watching  && g_z >= g_buy.extreme  + InpPullbackZ; }

//====================================================================
// 🕒 SESSION (เวลาเปิด/ปิดตลาดรายสัปดาห์จาก SymbolInfoSessionTrade)
//====================================================================
bool BuildWeekBlocks() {
   WeekBlock raw[];
   int n = 0;
   for(int d = 0; d < 7; d++) {
      for(uint idx = 0; idx < 16; idx++) {
         datetime from = 0, to = 0;
         if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)d, idx, from, to)) break;
         long s = (long)d * DAY_SEC + (long)from;
         long e = (long)d * DAY_SEC + (long)to;
         if(e <= s) e += DAY_SEC;   // session ข้ามเที่ยงคืน
         ArrayResize(raw, n + 1);
         raw[n].s = s;
         raw[n].e = e;
         n++;
      }
   }
   g_block_count = 0;
   g_always_open = false;
   if(n == 0) return false;

   // เรียงตามเวลาเริ่ม
   for(int i = 1; i < n; i++) {
      WeekBlock key = raw[i];
      int j = i - 1;
      while(j >= 0 && raw[j].s > key.s) { raw[j + 1] = raw[j]; j--; }
      raw[j + 1] = key;
   }

   // รวม session ที่ต่อกัน / มีช่องว่างสั้น (พักรายวัน) ให้เป็นช่วงเดียว
   ArrayResize(g_blocks, n);
   for(int i = 0; i < n; i++) {
      if(g_block_count > 0 && raw[i].s - g_blocks[g_block_count - 1].e <= MERGE_GAP_SEC) {
         g_blocks[g_block_count - 1].e = MathMax(g_blocks[g_block_count - 1].e, raw[i].e);
      } else {
         g_blocks[g_block_count] = raw[i];
         g_block_count++;
      }
   }

   // รวมช่วงท้ายสัปดาห์กับช่วงต้นสัปดาห์ หากต่อกันข้ามคืนวันเสาร์→อาทิตย์
   if(g_block_count > 1 &&
      (g_blocks[0].s + WEEK_SEC) - g_blocks[g_block_count - 1].e <= MERGE_GAP_SEC) {
      g_blocks[g_block_count - 1].e = g_blocks[0].e + WEEK_SEC;
      for(int i = 1; i < g_block_count; i++) g_blocks[i - 1] = g_blocks[i];
      g_block_count--;
   }
   else if(g_block_count == 1 &&
           (g_blocks[0].s + WEEK_SEC) - g_blocks[0].e <= MERGE_GAP_SEC) {
      g_always_open = true;   // ตลาดเปิดตลอดสัปดาห์
   }
   ArrayResize(g_blocks, g_block_count);
   return (g_block_count > 0);
}

bool LocateBlock(datetime now) {
   if(g_blk_valid && now >= g_blk_open && now < g_blk_close) return true;

   g_blk_valid = false;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime week_start = now - (datetime)(dt.day_of_week * DAY_SEC + dt.hour * 3600 + dt.min * 60 + dt.sec);
   long t = (long)(now - week_start);

   for(int i = 0; i < g_block_count; i++) {
      long s = g_blocks[i].s, e = g_blocks[i].e;
      if(t >= s && t < e) {
         g_blk_open  = week_start + (datetime)s;
         g_blk_close = week_start + (datetime)e;
         g_blk_valid = true;
         return true;
      }
      if(t + WEEK_SEC >= s && t + WEEK_SEC < e) {   // ช่วงที่เริ่มสัปดาห์ก่อนแล้วลากข้ามมา
         g_blk_open  = week_start + (datetime)(s - WEEK_SEC);
         g_blk_close = week_start + (datetime)(e - WEEK_SEC);
         g_blk_valid = true;
         return true;
      }
   }
   return false;
}

int GetTimeState(datetime now) {
   if(!g_session_ok || g_always_open) return TS_OPEN;
   if(!LocateBlock(now)) return TS_CLOSED;
   if(now >= g_blk_close - (datetime)(InpCloseBeforeClose_Min * 60)) return TS_CLOSING;
   if(now <  g_blk_open  + (datetime)(InpNoTradeAfterOpen_Min * 60)) return TS_WAIT_OPEN;
   return TS_OPEN;
}

string TimeStateText(int ts, datetime now) {
   if(!g_session_ok)  return "⚠️ ไม่มีข้อมูล Session (ไม่กรองเวลา)";
   if(g_always_open)  return "ตลาดเปิดตลอด (ไม่กรองเวลา)";
   switch(ts) {
      case TS_OPEN:
         return "✅ เทรดได้ | อีก " + FormatDuration((long)(g_blk_close - (datetime)(InpCloseBeforeClose_Min * 60) - now)) + " จะเริ่มบังคับปิด";
      case TS_WAIT_OPEN:
         return "⏳ ห้ามเข้า (ชั่วโมงแรกหลังเปิดสัปดาห์) | อีก " + FormatDuration((long)(g_blk_open + (datetime)(InpNoTradeAfterOpen_Min * 60) - now));
      case TS_CLOSING:
         return "🛑 ช่วงบังคับปิดก่อนตลาดปิด | ตลาดปิดในอีก " + FormatDuration((long)(g_blk_close - now));
   }
   return "💤 ตลาดปิด";
}

//====================================================================
// 🧯 COOLDOWN หลังชน SL & งดเปิดแท่งหลังตัดจบตามเวลา
//====================================================================
// ตรวจ deal ปิดไม้: ชน SL แบบขาดทุน → ตั้งเวลาพัก / ปิดโดย EA ในแท่งปัจจุบัน → งดแท่ง (ใช้ตอนกู้สถานะ)
void InspectClosingDeal(ulong deal, bool restore_bar_block, datetime bar0) {
   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   long     reason    = HistoryDealGetInteger(deal, DEAL_REASON);
   datetime deal_time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);

   if(reason == DEAL_REASON_SL && InpSLCooldown_Min > 0) {
      double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(deal, DEAL_SWAP) +
                   HistoryDealGetDouble(deal, DEAL_COMMISSION);
      if(pnl < 0.0) {
         datetime until = deal_time + (datetime)(InpSLCooldown_Min * 60);
         if(until > g_cooldown_until) {
            g_cooldown_until = until;
            g_last_status    = StringFormat("ชน SL ขาดทุน → พักเข้าไม้ถึง %s", TimeToString(until, TIME_MINUTES|TIME_SECONDS));
            PrintFormat("🧯 ชน SL ขาดทุน (deal #%I64u, %.2f) → พักเข้าไม้ %d นาที", deal, pnl, InpSLCooldown_Min);
         }
      }
   }
   if(restore_bar_block && reason == DEAL_REASON_EXPERT && bar0 > 0 && deal_time >= bar0)
      g_block_bar = bar0;
}

// กู้สถานะพัก / งดแท่ง จากประวัติล่าสุดเมื่อ EA เริ่มใหม่
void RestoreGuardsFromHistory() {
   datetime now  = ServerNow();
   datetime bar0 = CurrentZBarTime();
   long     back = MathMax((long)InpSLCooldown_Min * 60, (long)PeriodSeconds(InpZ_Timeframe)) + 60;
   if(!HistorySelect(now - (datetime)back, now + 60)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++) {
      ulong deal = HistoryDealGetTicket(i);
      if(deal > 0) InspectClosingDeal(deal, true, bar0);
   }
}

//====================================================================
// 💼 ORDER MANAGEMENT
//====================================================================
bool OpenOrder(int dir, double bid, double ask) {
   double lot  = NormalizeLot(InpLot);
   double sl_d = PtsToPrice(InpSL_Pts);
   double tp_d = PtsToPrice(InpTP_Pts);
   string cmt  = StringFormat("%s Z%+.2f", InpOrderComment, g_z);
   bool   ok;

   if(dir == -1) ok = trade.Sell(lot, _Symbol, bid, ND(bid + sl_d), ND(bid - tp_d), cmt);
   else          ok = trade.Buy (lot, _Symbol, ask, ND(ask - sl_d), ND(ask + tp_d), cmt);

   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      PrintFormat("✅ เปิด %s %.2f lot @ %s | Z = %+.2f (สุดขั้ว %+.2f)", (dir == -1 ? "SELL" : "BUY"), lot,
                  DoubleToString(trade.ResultPrice(), _Digits), g_z, (dir == -1 ? g_sell.extreme : g_buy.extreme));
      return true;
   }
   PrintFormat("❌ เปิด %s ไม่สำเร็จ: %u %s", (dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
   return false;
}

void TryEntries(int ts, double bid, double ask) {
   bool want_sell = SellTriggered();
   bool want_buy  = BuyTriggered();
   if(!want_sell && !want_buy) return;

   int    dir  = want_sell ? -1 : 1;
   string side = (dir == -1) ? "SELL" : "BUY";
   datetime now = ServerNow();

   if(ts != TS_OPEN) { g_last_status = side + " ผ่านเงื่อนไข แต่ติดช่วงเวลาห้ามเข้า"; return; }
   if(now < g_cooldown_until) {
      g_last_status = side + " ผ่านเงื่อนไข แต่อยู่ในช่วงพักหลังชน SL (อีก " + FormatDuration((long)(g_cooldown_until - now)) + ")";
      return;
   }
   if(g_block_bar != 0 && g_block_bar == g_zbar_time) {
      g_last_status = side + " ผ่านเงื่อนไข แต่งดเปิดแท่งนี้ (เพิ่งตัดจบตามเวลา)";
      return;
   }
   if(now < g_shock_until) {
      g_last_status = side + " ผ่านเงื่อนไข แต่ติดตัวจับช็อก (อีก " + FormatDuration((long)(g_shock_until - now)) + ")";
      return;
   }
   string news_name;
   if(InNewsWindow(now, news_name)) {
      g_last_status = side + " ผ่านเงื่อนไข แต่อยู่ในช่วงข่าว: " + news_name;
      return;
   }
   if(PersistBlocked(dir)) {
      g_last_status = StringFormat("%s ผ่านเงื่อนไข แต่แท่งก่อนหน้าปิดค้างโซนสุดขั้ว (Z ปิดแท่ง %+.2f)", side, g_prev_close_z);
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      g_last_status = side + " ผ่านเงื่อนไข แต่ปิด Algo Trading อยู่";
      return;
   }
   double spread_pts = PriceToPts(ask - bid);
   if(spread_pts > InpMaxSpread_Pts) {
      g_last_status = StringFormat("%s ผ่านเงื่อนไข แต่สเปรด %.0f > %.0f จุด", side, spread_pts, InpMaxSpread_Pts);
      return;
   }
   if(now < g_next_try) return;

   int buys, sells;
   CountPositions(buys, sells);
   if(buys + sells >= InpMaxPositions) {
      g_last_status = StringFormat("%s ผ่านเงื่อนไข แต่ครบ %d ไม้แล้ว", side, InpMaxPositions);
      return;
   }
   if((dir == -1 && buys > 0) || (dir == 1 && sells > 0)) {
      g_last_status = side + " ผ่านเงื่อนไข แต่มีไม้ฝั่งตรงข้ามค้างอยู่";
      return;
   }

   double extreme = (dir == -1) ? g_sell.extreme : g_buy.extreme;
   if(OpenOrder(dir, bid, ask)) {
      if(dir == -1) ResetSide(g_sell);
      else          ResetSide(g_buy);
      g_last_status = StringFormat("เปิด %s ที่ Z = %+.2f (สุดขั้ว %+.2f)", side, g_z, extreme);
   } else {
      g_next_try    = now + 1;   // กันยิงคำสั่งรัว ๆ เมื่อโบรกปฏิเสธ
      g_last_status = side + " ส่งคำสั่งไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

void CloseAllPositions() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      if(trade.PositionClose(ticket))
         PrintFormat("🛑 ปิดไม้ #%I64u ก่อนตลาดปิดสัปดาห์", ticket);
      else
         PrintFormat("❌ ปิดไม้ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

// ขยับโล่ของไม้ที่เลือกไว้ (ขยับทางเดียว + เคารพ Stops/Freeze Level)
void TrailPosition(ulong ticket, bool is_buy, double sl, double tp, double bid, double ask,
                   double dist, double stops, double freeze) {
   double new_sl;
   if(is_buy) {
      new_sl = ND(bid - dist);
      if(sl > 0.0 && new_sl - sl < _Point) return;
      if(bid - new_sl < stops) return;
      if(sl > 0.0 && bid - sl <= freeze) return;
      if(tp > 0.0 && tp - bid <= freeze) return;
   } else {
      new_sl = ND(ask + dist);
      if(sl > 0.0 && sl - new_sl < _Point) return;
      if(new_sl - ask < stops) return;
      if(sl > 0.0 && sl - ask <= freeze) return;
      if(tp > 0.0 && ask - tp <= freeze) return;
   }
   if(!trade.PositionModify(ticket, new_sl, tp))
      PrintFormat("⚠️ ขยับโล่ #%I64u ไม่สำเร็จ: %u %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

// เรียกทุก 1 วินาที: เปิดระบบไล่จี้ / ตัดจบตามเวลา / ขยับโล่ตามรอบ
void ManagePositions(datetime now) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;

   bool trail_cycle = (now - g_last_trail >= InpTrailInterval_Sec);
   if(trail_cycle) g_last_trail = now;

   double start  = PtsToPrice(InpTrailStart_Pts);
   double dist   = PtsToPrice(InpTrailDist_Pts);
   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;

   PruneActivated();

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;

      bool     is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl     = PositionGetDouble(POSITION_SL);
      double   tp     = PositionGetDouble(POSITION_TP);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double   prof   = is_buy ? (bid - open) : (open - ask);

      // ไม้ที่ SL ล็อกกำไรแล้ว (เช่นหลังรีสตาร์ท EA) ถือว่าระบบไล่จี้ทำงานแล้ว
      bool locked = (sl > 0.0) && (is_buy ? (sl > open) : (sl < open));
      if(locked) MarkActivated(ticket);

      if(!IsActivated(ticket)) {
         if(prof >= start) {
            // กำไรถึงจุดเริ่มไล่จี้ → เปิดระบบไล่จี้ทันที (ไม่รอรอบ 5 วินาที)
            MarkActivated(ticket);
            PrintFormat("🔥 #%I64u เริ่มไล่จี้ (กำไร %.0f จุด หลังเปิด %d วินาที)", ticket, PriceToPts(prof), (int)(now - opened));
            TrailPosition(ticket, is_buy, sl, tp, bid, ask, dist, stops, freeze);
         }
         else if(InpQuickWindow_Sec > 0 && now - opened >= InpQuickWindow_Sec) {
            // ครบเวลาแล้วไม่ดีดกลับ → ตัดจบ + งดเปิดไม้ทั้งแท่งนี้
            if(trade.PositionClose(ticket)) {
               g_block_bar   = CurrentZBarTime();
               g_last_status = StringFormat("ตัดจบ #%I64u (ไม่ดีดกลับใน %d วินาที, %+.0f จุด) → งดเปิดแท่งนี้",
                                            ticket, InpQuickWindow_Sec, PriceToPts(prof));
               PrintFormat("⏱️ %s", g_last_status);
            } else {
               PrintFormat("❌ ตัดจบ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
            }
         }
         continue;
      }

      if(trail_cycle) TrailPosition(ticket, is_buy, sl, tp, bid, ask, dist, stops, freeze);
   }
}

//====================================================================
// 🎨 DISPLAY
//====================================================================
void MoveHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string tip, double &cache) {
   if(MathAbs(price - cache) < _Point && ObjectFind(0, name) >= 0) return;
   cache = price;
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE, ND(price));
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

void UpdateZLines() {
   if(!g_draw || !InpShowZLines || !g_z_valid) return;
   double p_main = g_center;
   double p_sell = g_center + InpSellZ * g_sigma;
   double p_buy  = g_center - InpBuyZ  * g_sigma;
   MoveHLine(LINE_MAIN, p_main, clrGold,      STYLE_DOT,  1, "เส้นกลาง Regression (Z = 0)", g_line_main);
   MoveHLine(LINE_SELL, p_sell, clrOrangeRed, STYLE_DASH, 1, StringFormat("เฝ้า SELL เมื่อ Z ≥ +%.2f", InpSellZ), g_line_sell);
   MoveHLine(LINE_BUY,  p_buy,  clrAqua,      STYLE_DASH, 1, StringFormat("เฝ้า BUY เมื่อ Z ≤ −%.2f", InpBuyZ),  g_line_buy);
}

string SideText(const SideState &s, bool is_sell) {
   if(s.watching) {
      double trig = is_sell ? (s.extreme - InpPullbackZ) : (s.extreme + InpPullbackZ);
      return StringFormat("👀 เฝ้า สุดขั้ว %+.2f → ยิงเมื่อ Z %s %+.2f", s.extreme, (is_sell ? "≤" : "≥"), trig);
   }
   if(s.armed)
      return StringFormat("✅ พร้อม รอ Z %s %+.2f", (is_sell ? "≥" : "≤"), (is_sell ? InpSellZ : -InpBuyZ));
   return StringFormat("⏳ ปลดไก รอ Z %s %+.2f", (is_sell ? "<" : ">"),
                       (is_sell ? InpSellZ - InpReArmBuffer : -InpBuyZ + InpReArmBuffer));
}

string GuardText(datetime now) {
   string out = "";
   if(now < g_cooldown_until) out += "🧯 พักหลังชน SL อีก " + FormatDuration((long)(g_cooldown_until - now));
   if(g_block_bar != 0 && g_block_bar == CurrentZBarTime()) {
      if(out != "") out += " | ";
      out += "⛔ งดเปิดแท่งนี้ (ตัดจบตามเวลา)";
   }
   if(now < g_shock_until) {
      if(out != "") out += " | ";
      out += "⚡ ช็อก อีก " + FormatDuration((long)(g_shock_until - now));
   }
   if(InpUsePersistFilter && (g_prev_close_z >= InpPersistZ || g_prev_close_z <= -InpPersistZ)) {
      if(out != "") out += " | ";
      out += StringFormat("🧱 แท่งก่อนปิดค้างโซน (Z %+.2f) งดฝั่ง %s", g_prev_close_z, (g_prev_close_z > 0 ? "SELL" : "BUY"));
   }
   return (out == "") ? "ไม่มี" : out;
}

string PositionLines(double bid, double ask, datetime now) {
   string out = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      bool     is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl     = PositionGetDouble(POSITION_SL);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double   prof   = is_buy ? PriceToPts(bid - open) : PriceToPts(open - ask);
      double   locked = (sl > 0.0) ? (is_buy ? PriceToPts(sl - open) : PriceToPts(open - sl)) : 0.0;

      string st;
      if(IsActivated(ticket))
         st = StringFormat("🔥 ไล่จี้ ล็อก %+.0f", locked);
      else if(InpQuickWindow_Sec > 0) {
         long left = (long)InpQuickWindow_Sec - (long)(now - opened);
         if(left < 0) left = 0;
         st = StringFormat("⏱️ เหลือ %d วิ ต้องกำไรถึง %.0f", (int)left, InpTrailStart_Pts);
      }
      else
         st = StringFormat("รอกำไรถึง %.0f", InpTrailStart_Pts);

      out += StringFormat("\n  #%I64u %s %.2f @ %s | กำไร %+.0f จุด | SL %s | %s",
                          ticket, (is_buy ? "BUY" : "SELL"), PositionGetDouble(POSITION_VOLUME),
                          DoubleToString(open, _Digits), prof, DoubleToString(sl, _Digits), st);
   }
   return out;
}

void UpdateDashboard(int ts, datetime now) {
   if(!g_draw || !InpShowDashboard) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int buys, sells;
   CountPositions(buys, sells);

   string z_str = g_z_valid ? StringFormat("Z_reg %+.2f | Z_SMA %+.2f | เส้นกลาง %s | σ %.0f จุด%s",
                                           g_z, g_z_sma, DoubleToString(g_center, _Digits), PriceToPts(g_sigma),
                                           (g_sigma_floor ? " (พื้นขั้นต่ำ)" : ""))
                            : "รอข้อมูลแท่งเทียน...";
   string atr_str = (InpUseShockFilter && g_atr > 0.0)
                    ? StringFormat("ATR%d %.0f จุด | ช่วงแกว่งแท่งนี้ %.1f×ATR (ช็อกที่ %.1f×)",
                                   InpShockATR_Period, PriceToPts(g_atr), (g_bar0_hi - g_bar0_lo) / g_atr, InpShockATR_Mult)
                    : "ตัวจับช็อกปิดอยู่";
   string news_str = NextNewsText(now);

   string msg = "=== 📊 7-Lines Counter EA v3.00 (Regression Z + News Guard) ===\n";
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : %+.2f | %s%s\n", g_prev_close_z, atr_str, (news_str == "" ? "" : " | " + news_str));
   msg += StringFormat("SELL (Z ≥ +%.2f) : %s\n", InpSellZ, SideText(g_sell, true));
   msg += StringFormat("BUY  (Z ≤ −%.2f) : %s\n", InpBuyZ,  SideText(g_buy,  false));
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d (รวม %d/%d) | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, buys + sells, InpMaxPositions, PriceToPts(ask - bid), InpMaxSpread_Pts);
   msg += "ตัวกั้น : " + GuardText(now) + "\n";
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
   msg += "สถานะล่าสุด : " + g_last_status;
   msg += PositionLines(bid, ask, now);

   if(msg != g_last_comment) {
      g_last_comment = msg;
      Comment(msg);
   }
}

void Attach7Lines() {
   if(!g_draw || !InpShow7Lines) return;
   // ส่งค่า Input ตามลำดับของ Indicator v8.82 — ปิดลูกศร ป้าย Dashboard และเส้น Z ของ Indicator (EA วาดเอง)
   g_ind_handle = iCustom(_Symbol, PERIOD_CURRENT, IND_NAME,
                          1.00, 10000.0, 10000.0, 10000.0,                    // กลุ่ม 1
                          1.40, 3, 2.50, 2, 3.00,                             // กลุ่ม 2
                          5000.0, 50.0, 25.0,                                 // กลุ่ม 3
                          5000.0, 500.0, 10000.0, 2000.0, 20000.0, 3000.0,    // กลุ่ม 4
                          2000.0, 500.0, 3000.0, 1000.0, 5000.0, 2000.0, 1.00, 1000.0, // กลุ่ม 5
                          InpZ_Period, InpFastPeriod,                         // กลุ่ม 6
                          false, 220.0, 10, false, 2, false,                  // กลุ่ม 7
                          false, false, false, false, false, 450.0, 1000, 1000); // กลุ่ม 8
   if(g_ind_handle == INVALID_HANDLE) {
      Print("⚠️ โหลด Indicator 7 เส้นไม่ได้ — วาง Seven_Lines_Exhaustion_Ind.ex5 ไว้ใน MQL5/Indicators/");
      return;
   }
   if(!ChartIndicatorAdd(0, 0, g_ind_handle))
      PrintFormat("⚠️ แนบ Indicator 7 เส้นลงกราฟไม่ได้ (error %d)", GetLastError());
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
int OnInit() {
   if(InpZ_Period < 2 || InpFastPeriod < 2) { Print("❌ Period ต้องอย่างน้อย 2"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpSellZ <= 0.0 || InpBuyZ <= 0.0 || InpReArmBuffer < 0.0 || InpPullbackZ < 0.0) {
      Print("❌ ค่า Z ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLot <= 0.0 || InpMaxPositions < 1) { Print("❌ Lot / จำนวนไม้ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpTP_Pts <= 0.0 || InpSL_Pts <= 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpQuickWindow_Sec < 0 || InpSLCooldown_Min < 0) {
      Print("❌ เวลาตัดจบ / เวลาพัก ต้องไม่ติดลบ");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSigmaFloorMult < 0.0 || InpShockATR_Period < 1 || InpShockATR_Mult <= 0.0 || InpShockBlock_Min < 0 ||
      InpPersistZ <= 0.0 || InpNewsBefore_Min < 0 || InpNewsAfter_Min < 0) {
      Print("❌ ค่าตัวกรองข่าว / ช็อก / ความต่อเนื่อง / พื้นตัวหาร ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpUseNewsCalendar && MQLInfoInteger(MQL_TESTER))
      Print("ℹ️ ปฏิทินข่าวใช้ไม่ได้ใน Strategy Tester — ใช้เฉพาะตัวจับช็อกและกรองความต่อเนื่อง");
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Print("❌ EA นี้ต้องใช้บัญชีแบบ Hedging (บัญชี Netting จะรวมไม้เป็นโพซิชันเดียว)");
      return(INIT_FAILED);
   }
   if(InpPullbackZ >= InpReArmBuffer && InpReArmBuffer > 0.0)
      Print("⚠️ InpPullbackZ ≥ InpReArmBuffer: ถ้าจุดสุดขั้วอยู่ใกล้เกณฑ์ การเฝ้าจะถูกยกเลิกก่อนถึงจุดยิง");

   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   g_draw  = !(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));

   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints((ulong)MathMax(0.0, PtsToPrice(InpSlippage_Pts) / _Point));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_session_ok = BuildWeekBlocks();
   if(!g_session_ok) Print("⚠️ อ่านเวลา Session ของ Symbol ไม่ได้ — ปิดการกรองเวลาตลาด");

   if(StringFind(_Symbol, "XAU") < 0) PrintFormat("⚠️ EA ออกแบบสำหรับ XAUUSD แต่กำลังรันบน %s", _Symbol);
   if(InpShow7Lines && Period() != InpZ_Timeframe)
      PrintFormat("ℹ️ กราฟเป็น %s แต่ Z ใช้ %s — เส้น 7 เส้นจะคำนวณตาม TF ของกราฟ", EnumToString(Period()), EnumToString(InpZ_Timeframe));

   // เริ่มต้นแบบปลดไก: ต้องรอ Z ถอยกลับก่อนจึงเฝ้าได้ (กันเข้ากลางทางเมื่อเปิด EA ตอน Z เกินเกณฑ์อยู่แล้ว)
   ResetSide(g_sell);
   ResetSide(g_buy);
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_last_trail     = 0;
   g_next_try       = 0;
   g_cooldown_until = 0;
   g_block_bar      = 0;
   g_shock_until    = 0;
   g_news_loaded    = 0;
   g_atr            = 0.0;
   g_prev_close_z   = 0.0;
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   g_last_comment   = "";
   g_line_main = g_line_sell = g_line_buy = 0.0;
   ArrayResize(g_activated, 0);

   RestoreGuardsFromHistory();
   RefreshNews(ServerNow());

   ObjectsDeleteAll(0, OBJ_PREFIX);
   Attach7Lines();

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   if(g_ind_handle != INVALID_HANDLE) {
      ChartIndicatorDelete(0, 0, IND_SHORTNAME);
      IndicatorRelease(g_ind_handle);
      g_ind_handle = INVALID_HANDLE;
   }
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
}

void OnTick() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;
   if(!UpdateZ(bid)) return;

   CheckShockLive();
   UpdateSides();

   int ts = GetTimeState(ServerNow());
   if(ts == TS_CLOSING) {
      CloseAllPositions();
      return;
   }
   TryEntries(ts, bid, ask);
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ / จัดการไม้ (เปิดไล่จี้, ตัดจบตามเวลา, ขยับโล่)
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManagePositions(now);

   // 2. อัปเดตการแสดงผล (Z คำนวณจาก Bid ล่าสุด ไม่กระทบสถานะไกยิง)
   if(g_draw) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid > 0.0) UpdateZ(bid);
      UpdateZLines();
      UpdateDashboard(ts, now);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   InspectClosingDeal(trans.deal, false, 0);
}
//+------------------------------------------------------------------+
