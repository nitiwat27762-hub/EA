//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Counter-Trend Z-Score EA for XAUUSD (based on Indicator v8.82)|
//+------------------------------------------------------------------+
//
// 📋 สรุปตรรกะ
//  • Z = (Bid − SMA) / StdDev ของ TF ที่ตั้ง (ค่าเริ่มต้น M15, 20 แท่ง) โดยใช้ Bid แทนราคาปิดแท่งปัจจุบัน
//  • SELL (Market) เมื่อ Z ≥ +InpSellZ  |  BUY (Market) เมื่อ Z ≤ −InpBuyZ
//  • หลังเปิดไม้ ฝั่งนั้นจะ "ปลดไก" จนกว่า Z จะถอยกลับเกินระยะ InpReArmBuffer
//    (SELL: Z < SellZ − buffer | BUY: Z > −BuyZ + buffer) — ตอนเริ่ม EA ก็ต้องรอเงื่อนไขนี้ก่อน
//  • สูงสุด InpMaxPositions ไม้ (รวมทั้งสองฝั่ง) และห้ามถือ BUY กับ SELL พร้อมกัน
//  • TP / SL คงที่ + ไล่จี้กำไรทุก InpTrailInterval_Sec วินาที (SL ขยับทางเดียว)
//  • ห้ามเข้า 1 ชม.แรกหลังตลาดเปิดสัปดาห์ / ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์ (อ่านจาก Session ของ Symbol)
//  • จุด (Points) อ้างอิงทองทศนิยม 3 ตำแหน่ง — โบรก 2 ตำแหน่งแปลงอัตโนมัติ
//
// ⚡ การประหยัด CPU
//  • ผลรวม/ผลรวมกำลังสองของแท่งที่ปิดแล้วถูกแคชไว้ คำนวณใหม่เฉพาะตอนขึ้นแท่งใหม่ → ต่อ Tick ใช้แค่ไม่กี่บรรทัดคณิต
//  • ไล่จี้ / ปิดก่อนตลาดปิด / Dashboard / เส้น ทำงานบน OnTimer (1 วินาที) ไม่ใช่ทุก Tick
//  • Dashboard เขียนใหม่เฉพาะเมื่อข้อความเปลี่ยน, เส้นขยับเฉพาะเมื่อราคาเปลี่ยน
//  • ใน Strategy Tester แบบไม่เปิด Visual จะไม่วาดอะไรเลย
//
#property copyright   "Commander's Quant System"
#property version     "1.00"
#property description "ไม้สวนเทรนด์ด้วย Z-Score สำหรับ XAUUSD (บัญชี Hedging)"
#property tester_indicator "Seven_Lines_Exhaustion_Ind.ex5"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpSellZ             = 2.50;       // SELL เมื่อ Z ≥ +ค่านี้ (สวนขาขึ้น)
input double          InpBuyZ              = 3.00;       // BUY เมื่อ Z ≤ −ค่านี้ (สวนขาลง)
input double          InpReArmBuffer       = 0.50;       // ระยะ Z ที่ต้องถอยกลับก่อนยิงไม้ถัดไปฝั่งเดิม

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
input int             InpTrailInterval_Sec = 5;          // อัปเดตโล่ทุกกี่วินาที

input group "=== 4. ตัวกรอง ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)

input group "=== 5. การแสดงผล ==="
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

CTrade   trade;
double   g_pmult        = 1.0;
bool     g_draw         = true;

// --- Z engine (แคชแท่งที่ปิดแล้ว) ---
datetime g_zbar_time    = 0;
bool     g_z_ready      = false;
double   g_ref          = 0.0;
double   g_sumS         = 0.0;
double   g_sumQ         = 0.0;
bool     g_z_valid      = false;
double   g_z            = 0.0;
double   g_mean         = 0.0;
double   g_std          = 0.0;

// --- ไกยิงแต่ละฝั่ง ---
bool     g_sell_armed   = false;
bool     g_buy_armed    = false;
datetime g_next_try     = 0;
string   g_last_status  = "เริ่มทำงาน";

// --- Session ---
WeekBlock g_blocks[];
int       g_block_count  = 0;
bool      g_always_open  = false;
bool      g_session_ok   = false;
datetime  g_blk_open     = 0;
datetime  g_blk_close    = 0;
bool      g_blk_valid    = false;

// --- ไล่จี้ / UI ---
datetime g_last_trail   = 0;
string   g_last_comment = "";
double   g_line_main    = 0.0;
double   g_line_sell    = 0.0;
double   g_line_buy     = 0.0;
int      g_ind_handle   = INVALID_HANDLE;

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

//====================================================================
// 📐 Z-SCORE ENGINE
//   แท่งที่ปิดแล้ว (Period−1 แท่ง) ถูกแคชเป็นผลรวมแบบเลื่อนจุดอ้างอิง (ลดความคลาดเคลื่อนทศนิยม)
//   ต่อ Tick แค่บวก Bid เข้าไปแล้วคำนวณ Mean / StdDev แบบ Population (ตรงกับ Indicator v8.82)
//====================================================================
bool RefreshClosedBars() {
   datetime t0 = iTime(_Symbol, InpZ_Timeframe, 0);
   if(t0 == 0) return false;
   if(g_z_ready && t0 == g_zbar_time) return true;

   int    need = InpZ_Period - 1;
   double c[];
   if(CopyClose(_Symbol, InpZ_Timeframe, 1, need, c) != need) {
      g_z_ready = false;
      return false;
   }
   g_ref  = c[need - 1];
   g_sumS = 0.0;
   g_sumQ = 0.0;
   for(int k = 0; k < need; k++) {
      double x = c[k] - g_ref;
      g_sumS += x;
      g_sumQ += x * x;
   }
   g_zbar_time = t0;
   g_z_ready   = true;
   return true;
}

bool UpdateZ(double bid) {
   g_z_valid = false;
   if(!RefreshClosedBars()) return false;

   double n   = (double)InpZ_Period;
   double x   = bid - g_ref;
   double m   = (g_sumS + x) / n;
   double var = (g_sumQ + x * x) / n - m * m;
   if(var <= 0.0) return false;

   g_std     = MathSqrt(var);
   g_mean    = g_ref + m;
   g_z       = (bid - g_mean) / g_std;
   g_z_valid = true;
   return true;
}

void UpdateArming() {
   if(!g_sell_armed && g_z < InpSellZ - InpReArmBuffer)  g_sell_armed = true;
   if(!g_buy_armed  && g_z > -InpBuyZ + InpReArmBuffer)  g_buy_armed  = true;
}

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
      PrintFormat("✅ เปิด %s %.2f lot @ %s | Z = %+.2f", (dir == -1 ? "SELL" : "BUY"), lot,
                  DoubleToString(trade.ResultPrice(), _Digits), g_z);
      return true;
   }
   PrintFormat("❌ เปิด %s ไม่สำเร็จ: %u %s", (dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
   return false;
}

void TryEntries(int ts, double bid, double ask) {
   bool want_sell = g_sell_armed && g_z >= InpSellZ;
   bool want_buy  = g_buy_armed  && g_z <= -InpBuyZ;
   if(!want_sell && !want_buy) return;

   int dir = want_sell ? -1 : 1;
   string side = (dir == -1) ? "SELL" : "BUY";

   if(ts != TS_OPEN) { g_last_status = side + " ผ่าน Z แต่ติดช่วงเวลาห้ามเข้า"; return; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      g_last_status = side + " ผ่าน Z แต่ปิด Algo Trading อยู่";
      return;
   }
   double spread_pts = PriceToPts(ask - bid);
   if(spread_pts > InpMaxSpread_Pts) {
      g_last_status = StringFormat("%s ผ่าน Z แต่สเปรด %.0f > %.0f จุด", side, spread_pts, InpMaxSpread_Pts);
      return;
   }
   datetime now = TimeCurrent();
   if(now < g_next_try) return;

   int buys, sells;
   CountPositions(buys, sells);
   if(buys + sells >= InpMaxPositions) {
      g_last_status = StringFormat("%s ผ่าน Z แต่ครบ %d ไม้แล้ว", side, InpMaxPositions);
      return;
   }
   if((dir == -1 && buys > 0) || (dir == 1 && sells > 0)) {
      g_last_status = side + " ผ่าน Z แต่มีไม้ฝั่งตรงข้ามค้างอยู่";
      return;
   }

   if(OpenOrder(dir, bid, ask)) {
      if(dir == -1) g_sell_armed = false;
      else          g_buy_armed  = false;
      g_last_status = StringFormat("เปิด %s ที่ Z = %+.2f", side, g_z);
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

void ManageTrailing() {
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;

   double start  = PtsToPrice(InpTrailStart_Pts);
   double dist   = PtsToPrice(InpTrailDist_Pts);
   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double new_sl;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
         if(bid - open < start) continue;
         new_sl = ND(bid - dist);
         if(sl > 0.0 && new_sl - sl < _Point) continue;            // ขยับขึ้นอย่างเดียว
         if(bid - new_sl < stops) continue;
         if(sl > 0.0 && bid - sl <= freeze) continue;
         if(tp > 0.0 && tp - bid <= freeze) continue;
      } else {
         if(open - ask < start) continue;
         new_sl = ND(ask + dist);
         if(sl > 0.0 && sl - new_sl < _Point) continue;            // ขยับลงอย่างเดียว
         if(new_sl - ask < stops) continue;
         if(sl > 0.0 && sl - ask <= freeze) continue;
         if(tp > 0.0 && ask - tp <= freeze) continue;
      }

      if(!trade.PositionModify(ticket, new_sl, tp))
         PrintFormat("⚠️ ขยับโล่ #%I64u ไม่สำเร็จ: %u %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
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
   double p_main = g_mean;
   double p_sell = g_mean + InpSellZ * g_std;
   double p_buy  = g_mean - InpBuyZ  * g_std;
   MoveHLine(LINE_MAIN, p_main, clrGold,      STYLE_DOT,   1, "Main SMA (Z = 0)", g_line_main);
   MoveHLine(LINE_SELL, p_sell, clrOrangeRed, STYLE_DASH,  1, StringFormat("SELL เมื่อ Z ≥ +%.2f", InpSellZ), g_line_sell);
   MoveHLine(LINE_BUY,  p_buy,  clrAqua,      STYLE_DASH,  1, StringFormat("BUY เมื่อ Z ≤ −%.2f", InpBuyZ),  g_line_buy);
}

string PositionLines(double bid, double ask) {
   string out = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      bool   is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double prof   = is_buy ? PriceToPts(bid - open) : PriceToPts(open - ask);
      double locked = (sl > 0.0) ? (is_buy ? PriceToPts(sl - open) : PriceToPts(open - sl)) : 0.0;
      string trail  = (locked > 0.0) ? StringFormat("🔥 ไล่จี้ ล็อก %+.0f", locked)
                                     : StringFormat("รอกำไรถึง %.0f", InpTrailStart_Pts);
      out += StringFormat("\n  #%I64u %s %.2f @ %s | กำไร %+.0f จุด | SL %s | %s",
                          ticket, (is_buy ? "BUY" : "SELL"), PositionGetDouble(POSITION_VOLUME),
                          DoubleToString(open, _Digits), prof, DoubleToString(sl, _Digits), trail);
   }
   return out;
}

void UpdateDashboard(int ts, datetime now) {
   if(!g_draw || !InpShowDashboard) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int buys, sells;
   CountPositions(buys, sells);

   string z_str = g_z_valid ? StringFormat("%+.2f | Main %s | StdDev %.0f จุด", g_z, DoubleToString(g_mean, _Digits), PriceToPts(g_std))
                            : "รอข้อมูลแท่งเทียน...";
   string sell_st = g_sell_armed ? "✅ พร้อมยิง" : StringFormat("⏳ รอ Z < +%.2f", InpSellZ - InpReArmBuffer);
   string buy_st  = g_buy_armed  ? "✅ พร้อมยิง" : StringFormat("⏳ รอ Z > %+.2f", -InpBuyZ + InpReArmBuffer);

   string msg = "=== 📊 7-Lines Counter EA v1.00 ===\n";
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("SELL Z ≥ +%.2f : %s   |   BUY Z ≤ −%.2f : %s\n", InpSellZ, sell_st, InpBuyZ, buy_st);
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d (รวม %d/%d) | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, buys + sells, InpMaxPositions, PriceToPts(ask - bid), InpMaxSpread_Pts);
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
   msg += "สถานะล่าสุด : " + g_last_status;
   msg += PositionLines(bid, ask);

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
   if(InpSellZ <= 0.0 || InpBuyZ <= 0.0 || InpReArmBuffer < 0.0) { Print("❌ ค่า Z ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpLot <= 0.0 || InpMaxPositions < 1) { Print("❌ Lot / จำนวนไม้ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpTP_Pts <= 0.0 || InpSL_Pts <= 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Print("❌ EA นี้ต้องใช้บัญชีแบบ Hedging (บัญชี Netting จะรวมไม้เป็นโพซิชันเดียว)");
      return(INIT_FAILED);
   }

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

   // เริ่มต้นแบบปลดไก: ต้องรอ Z ถอยกลับก่อนจึงยิงได้ (กันเข้ากลางทางเมื่อเปิด EA ตอน Z เกินเกณฑ์อยู่แล้ว)
   g_sell_armed = false;
   g_buy_armed  = false;
   g_zbar_time  = 0;
   g_z_ready    = false;
   g_blk_valid  = false;
   g_last_trail = 0;
   g_last_comment = "";
   g_line_main = g_line_sell = g_line_buy = 0.0;

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

   UpdateArming();

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

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ (ลองซ้ำทุกวินาทีจนไม่เหลือไม้)
   if(ts == TS_CLOSING) CloseAllPositions();

   // 2. ไล่จี้กำไรทุก InpTrailInterval_Sec วินาที
   else if(now - g_last_trail >= InpTrailInterval_Sec) {
      g_last_trail = now;
      ManageTrailing();
   }

   // 3. อัปเดตการแสดงผล (Z คำนวณจาก Bid ล่าสุด ไม่กระทบไกยิง)
   if(g_draw) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid > 0.0) UpdateZ(bid);
      UpdateZLines();
      UpdateDashboard(ts, now);
   }
}
//+------------------------------------------------------------------+
