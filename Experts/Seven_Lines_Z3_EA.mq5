//+------------------------------------------------------------------+
//|                                            Seven_Lines_Z3_EA.mq5 |
//|   Z3 EA for XAUUSD: S1 ตามน้ำสด / S2 สวนที่ไส้ / S3 Stop ทะลุยอด   |
//+------------------------------------------------------------------+
//
// 🎯 3 ระบบ (สมมาตรทั้งสองทิศ, ตัวอย่างฝั่ง Z ขึ้น) — แยกจาก Seven_Lines_Counter_EA (ประวัติอยู่ใน README.md)
//  • S1 ตามน้ำสด : แท่งปัจจุบัน Z_reg หรือ Z_SMA > 2.0 → BUY Market ทันที, SL = ราคาเปิดของแท่งปัจจุบัน
//                 (ราคาอยู่ต่ำกว่าราคาเปิดแท่ง = วาง SL ไม่ได้ → ยังไม่ยิง)
//  • S2 สวนที่ไส้: แท่งปิดล่าสุด Z ที่ High > 2.5 → ราคาเข้าไส้บน (max(Open, Close) ถึง High) = สแตนบาย
//                 → Bid ไม่ทำ High ใหม่ของแท่งปัจจุบัน 10 วิ + High แท่งปัจจุบัน < High แท่งปิดล่าสุด → SELL Market
//                 SL จริงที่โบรก = High แท่งปิดล่าสุด + 2,000 (= ตัดจบเมื่อทำ High ใหม่เกิน 2,000)
//                 ยกเลิกสแตนบายเงื่อนไขเดียว: ราคาขึ้นเกิน High แท่งปิดล่าสุด (ปล่อยให้ S3 ทำงาน)
//  • S3 Stop ทะลุ: แท่งปิดล่าสุด Z ที่ High > 2.5 → เปิดแท่งใหม่วาง Buy Stop ที่ High แท่งปิดล่าสุด + 2,500
//                 SL = ราคาเปิดของแท่งปิดล่าสุด, ไม่ถูกเกี่ยวจนจบแท่ง → ยกเลิก (ราคาเกินจุดวางแล้ว = ข้าม)
//  • แต่ละระบบเปิดได้ครั้งเดียวต่อแท่ง M15 และถือได้ระบบละ 1 ไม้พร้อมกัน (บัญชี Hedging)
//
// 📋 การจัดการไม้ (ทุกระบบ, Lot 0.02)
//  • กำไรสูงสุดถึง 3,000 → SL ไปที่ทุน +500
//  • กำไรถึง 5,000 → ปิดครึ่ง lot, ครึ่งที่เหลือไล่จี้ SL ห่างราคา 4,000 จุด (ขยับทางเดียว)
//  • ไม่มี TP / ตัดจบตามเวลา (เปิดได้ด้วย InpExitBars) | ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//  • ห้ามเข้า 1 ชม.หลังตลาดเปิด / 1 ชม.ก่อนตลาดปิดสัปดาห์ | สเปรด ≤ 800
//
// 🧪 Tick Replay: เล่นซ้ำ tick จริงด้วยฟังก์ชันตัดสินใจชุดเดียวกับ EA จริง → มาร์ก + สรุป + CSV (MQL5/Files/7LZ3_Replay_<symbol>.csv)
// ⚡ งานเทรดทำต่อ Tick + Timer 200 ms ก่อนงานแสดงผลเสมอ (เวลา = tick ล่าสุด + นาฬิกาในเครื่อง)
//
#property copyright   "Commander's Quant System"
#property version     "1.00"
#property description "S1 ตามน้ำสด / S2 สวนที่ไส้แท่งก่อน / S3 Stop ทะลุยอด จากค่า Z สำหรับ XAUUSD (บัญชี Hedging)"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z / นับแท่ง
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z_reg ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ระบบเข้า (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ) ==="
input bool            InpEnableS1          = true;       // S1 ตามน้ำสด
input double          InpS1_Z              = 2.00;       // S1: Z_reg หรือ Z_SMA ของแท่งปัจจุบัน > ค่านี้ → ตามน้ำ
input bool            InpEnableS2          = true;       // S2 สวนที่ไส้แท่งปิดล่าสุด
input double          InpS2_PrevZ          = 2.50;       // S2: แท่งปิดล่าสุด Z ตัวใดตัวหนึ่งที่ High (SELL) / Low (BUY) > ค่านี้
input int             InpS2_NoNewSec       = 10;         // S2: ไม่มี High (SELL) / Low (BUY) ใหม่ครบกี่วินาที → ยิง
input double          InpS2_Cut_Pts        = 2000.0;     // S2: SL = High (SELL) / Low (BUY) แท่งปิดล่าสุด ± กี่จุด
input bool            InpEnableS3          = true;       // S3 Stop ทะลุยอด
input double          InpS3_PrevZ          = 2.50;       // S3: แท่งปิดล่าสุด Z ตัวใดตัวหนึ่งที่ High / Low > ค่านี้
input double          InpS3_Dist_Pts       = 2500.0;     // S3: Buy Stop เหนือ High / Sell Stop ใต้ Low ของแท่งปิดล่าสุดกี่จุด

input group "=== 3. การจัดการไม้ (ทุกระบบ) ==="
input double          InpLot               = 0.02;       // Lot
input double          InpLock_Trig_Pts     = 3000.0;     // เกราะ: กำไรสูงสุดถึงกี่จุด → SL ไปที่ทุน + InpLock_Pts (0 = ปิด)
input double          InpLock_Pts          = 500.0;      // เกราะ: SL ไปที่ราคาเข้า + กี่จุด (ฝั่งกำไร)
input double          InpPartial_Pts       = 5000.0;     // กำไรถึงกี่จุด → ปิดครึ่ง lot แล้วเริ่มไล่จี้ (0 = ปิด)
input double          InpTrail_Pts         = 4000.0;     // ไล่จี้: SL ห่างราคากี่จุด (ครึ่งที่เหลือ)
input double          InpTrailStep_Pts     = 100.0;      // ไล่จี้ (ไม้จริง): ขยับเมื่อดีขึ้นอย่างน้อยกี่จุด (ไม่เกิน 1 ครั้ง/วินาที)
input int             InpExitBars          = 0;          // ตัดจบที่ราคาปิดของแท่งที่ N หลังแท่งที่เข้า (0 = ปิด)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880300;     // Magic Number (แยกจาก Counter EA)
input string          InpOrderComment      = "7L-Z3";    // คอมเมนต์ออเดอร์ (ต่อท้ายด้วย S1 / S2 / S3)

input group "=== 4. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpNoTradeBeforeClose_Min = 60;    // ห้ามเข้าไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ + ลบออเดอร์รอก่อนตลาดปิดสัปดาห์ (นาที)

input group "=== 5. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowLevels        = true;       // แสดงโซนไส้ (S2) / ระดับ SL ของ S2 / ระดับ Stop ของ S3 บนแท่งปัจจุบัน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpReplayCSV         = true;       // Tick Replay: บันทึกไม้ลง CSV (MQL5/Files)

input group "=== 6. สี ==="
input color           InpClrS1             = clrDeepSkyBlue;    // ไม้ S1
input color           InpClrS2             = clrOrange;         // ไม้ S2
input color           InpClrS3             = clrMagenta;        // ไม้ S3
input color           InpClrWin            = clrLimeGreen;      // เส้นเข้า→ออก ไม้กำไร
input color           InpClrLoss           = clrTomato;         // เส้นเข้า→ออก ไม้ขาดทุน
input color           InpClrZone           = C'70,55,25';       // โซนไส้ (S2) รอราคา
input color           InpClrZoneOn         = C'120,70,20';      // โซนไส้ (S2) กำลังสแตนบาย
input color           InpClrLevel          = clrSilver;         // เส้นระดับ SL S2 / Stop S3

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define TS_OPEN       0
#define TS_WAIT_OPEN  1
#define TS_CLOSING    2
#define TS_CLOSED     3
#define TS_WAIT_CLOSE 4

#define RX_OPEN   0
#define RX_SL     1   // ชน SL แรก (S2 = ตัดจบที่ยอด + 2,000)
#define RX_LOCK   2   // ชน SL ที่เกราะขยับแล้ว
#define RX_TRAIL  3   // ชนโล่ไล่จี้
#define RX_WEEK   4   // บังคับปิดก่อนตลาดปิดสัปดาห์
#define RX_TIME   5   // ตัดจบตามเวลา

const string OBJ_PREFIX    = "7LZ3_";
const string BTN_PREFIX    = "7LZ3_BTN_S";
const long   WEEK_SEC      = 604800;
const long   DAY_SEC       = 86400;
const long   MERGE_GAP_SEC = 12 * 3600;
const int    RP_SKIP_SEC   = 30;       // ดึง tick ช่วงหนึ่งไม่สำเร็จนานเกินนี้ → ข้ามช่วงนั้น
const long   RP_BUDGET_US  = 150000;   // เล่นซ้ำได้ไม่เกินกี่ไมโครวินาทีต่อรอบ

struct WeekBlock {
   long s;   // วินาทีนับจากวันอาทิตย์ 00:00 (เวลาเซิร์ฟเวอร์)
   long e;
};

struct ZCache {
   bool   ok;
   double ref, sY, sXY, sYY, sD, sDD, last_close;
   double prev_zr, prev_zs;   // Z ตอนปิดแท่งล่าสุด
};

// บริบทของแท่งปัจจุบัน + แท่งปิดล่าสุด (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct Ctx {
   bool     ready;          // มีแคช Z + ข้อมูลแท่งปิดล่าสุดแล้ว
   datetime bar;            // เวลาแท่งปัจจุบัน (TF ของ Z)
   ZCache   zc;
   double   open, hi, lo;   // แท่งปัจจุบัน (High / Low จาก Bid)
   double   p_open, p_high, p_low, p_close;   // แท่งปิดล่าสุด
   double   p_zhi;          // แท่งปิดล่าสุด: Z ตัวที่สูงกว่าที่ High
   double   p_zlo;          // แท่งปิดล่าสุด: Z ตัวที่ต่ำกว่าที่ Low
   bool     zok;
   double   zr, zs;         // Z สด
   bool     done[4];        // ระบบ 1-3 เปิด / วางแล้วในแท่งนี้
   bool     sb[2];          // S2 สแตนบาย: [0] = สวนลง (SELL, ไส้บน) / [1] = สวนขึ้น (BUY, ไส้ล่าง)
   bool     sb_cancel[2];   // ราคาทะลุยอดแท่งปิดล่าสุดแล้ว → ยกเลิกทั้งแท่ง
   long     sb_last_new[2]; // เวลาที่ทำ High (SELL) / Low (BUY) ใหม่ล่าสุดระหว่างสแตนบาย
};

// สถานะการจัดการไม้ 1 ไม้ (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct PState {
   int    sys, dir;         // ระบบ 1-3, ทิศ +1 BUY / −1 SELL
   double entry, sl;
   double lot0, lot;        // lot ตอนเข้า / ตอนนี้
   double mfe;              // กำไรสูงสุด (ราคา)
   long   mfe_msc;
   long   open_msc;
   bool   partial;          // ปิดครึ่งแล้ว (หรือข้ามเพราะแบ่ง lot ไม่ได้)
   int    stage;            // 0 = SL แรก / 1 = เกราะ / 2 = ไล่จี้
};

CTrade    trade;
double    g_pmult        = 1.0;
bool      g_draw         = true;
bool      g_en[4];                    // เปิดใช้ระบบ 1-3 (ปุ่มบนกราฟ)

// --- Session ---
WeekBlock g_blocks[];
int       g_block_count  = 0;
bool      g_always_open  = false;
bool      g_session_ok   = false;
datetime  g_blk_open     = 0;
datetime  g_blk_close    = 0;
bool      g_blk_valid    = false;

// --- EA จริง ---
Ctx       g_c;
long      g_last_tick_msc = 0;
uint      g_tick_local    = 0;        // GetTickCount ตอน tick ล่าสุด (นาฬิกาเสริม)
datetime  g_next_try[4];              // ส่งคำสั่งของระบบไม่สำเร็จ → ลองใหม่หลังเวลานี้
datetime  g_del_retry     = 0;
uint      g_heavy_ms      = 0;
string    g_last_status   = "เริ่มทำงาน";
string    g_last_comment  = "";

struct PosMon {
   ulong  tk;
   PState ps;
   long   last_mod;   // ขยับ SL ล่าสุด (msc)
   long   next_try;   // สั่งไม่สำเร็จ → ลองใหม่หลังเวลานี้ (msc)
};
PosMon    g_pm[];

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

string ShortSec(long sec) {
   if(sec < 0)    sec = 0;
   if(sec < 60)   return StringFormat("%dวิ", (int)sec);
   if(sec < 3600) return StringFormat("%dน.%02d", (int)(sec / 60), (int)(sec % 60));
   return StringFormat("%dชม.%02d", (int)(sec / 3600), (int)((sec % 3600) / 60));
}

datetime BarStartOf(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   return (per > 0) ? (datetime)((long)t - (long)t % per) : t;
}


// เวลาตอนนี้ (msc, นาฬิกาเซิร์ฟเวอร์): เวลา tick ล่าสุด + เวลาที่ผ่านไปตามนาฬิกาในเครื่อง — แม่นแม้ tick ห่าง
long NowMsc() {
   long srv = (long)ServerNow() * 1000;
   if(g_last_tick_msc <= 0) return srv;
   return MathMax(g_last_tick_msc + (long)(GetTickCount() - g_tick_local), srv);
}

string SysTag(int sys) { return "S" + IntegerToString(sys); }

int SysFromComment(string c) {
   for(int s = 1; s <= 3; s++)
      if(StringFind(c, InpOrderComment + " " + SysTag(s)) >= 0) return s;
   return 0;
}

color SysColor(int sys) { return (sys == 1) ? InpClrS1 : ((sys == 2) ? InpClrS2 : InpClrS3); }

//====================================================================
// 🧮 Z (สูตรเดียวกับ Counter EA)
//====================================================================
bool ComputeZ(double sy, double sxy, double syy, double y_last, double sd, double sdd,
              double &z_reg, double &z_sma, double &fit, double &sigma, bool &floored,
              double &mean, double &sd_sma) {
   double n   = (double)InpZ_Period;
   double sx  = n * (n - 1.0) / 2.0;
   double sxx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;

   mean          = sy / n;
   double var_sm = syy / n - mean * mean;
   if(var_sm <= 0.0) return false;
   sd_sma        = MathSqrt(var_sm);

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

bool BuildZCache(const double &c[], ZCache &zc) {
   int n = InpZ_Period;
   zc.ok  = false;
   zc.ref = c[n - 1];

   // 1. Z ตอนปิดแท่งล่าสุด (n แท่งปิด, แท่งล่าสุดอยู่ x = n-1)
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n; k++) {
      double y = c[k] - zc.ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[k] - c[k - 1]; sd += d; sdd += d * d; }
   }
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(ComputeZ(sy, sxy, syy, 0.0, sd, sdd, zr, zs, fit, sig, fl, mn, ssd)) { zc.prev_zr = zr; zc.prev_zs = zs; }
   else                                                                     { zc.prev_zr = 0.0; zc.prev_zs = 0.0; }

   // 2. แคชแท่งปิด n-1 แท่งล่าสุดสำหรับคำนวณสด (x = 0..n-2) + ส่วนต่างระหว่างแท่งปิด (n-2 ค่า)
   zc.sY = 0.0; zc.sXY = 0.0; zc.sYY = 0.0; zc.sD = 0.0; zc.sDD = 0.0;
   for(int k = 1; k < n; k++) {
      double y = c[k] - zc.ref;
      int    x = k - 1;
      zc.sY += y; zc.sXY += x * y; zc.sYY += y * y;
      if(k > 1) { double d = c[k] - c[k - 1]; zc.sD += d; zc.sDD += d * d; }
   }
   zc.last_close = c[n - 1];
   zc.ok = true;
   return true;
}

bool ZAtPrice(const ZCache &zc, double price, double &zr, double &zs,
              double &fit, double &sig, bool &fl, double &mn, double &ssd) {
   if(!zc.ok) return false;
   double n  = (double)InpZ_Period;
   double y  = price - zc.ref;
   double d0 = price - zc.last_close;
   return ComputeZ(zc.sY + y, zc.sXY + (n - 1.0) * y, zc.sYY + y * y, y,
                   zc.sD + d0, zc.sDD + d0 * d0, zr, zs, fit, sig, fl, mn, ssd);
}

// Z ของแท่ง j ที่ราคา price (ราคาปิด n−1 แท่งก่อนหน้า + price)
bool ZForBarPrice(const double &c[], int j, double price, double &z_reg, double &z_sma) {
   int n = InpZ_Period;
   if(j < n - 1) return false;
   double ref = c[j - 1];
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n - 1; k++) {
      int    idx = j - (n - 1) + k;
      double y   = c[idx] - ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[idx] - c[idx - 1]; sd += d; sdd += d * d; }
   }
   double y = price - ref;
   sy += y; sxy += (n - 1) * y; syy += y * y;
   double d0 = price - c[j - 1];
   sd += d0; sdd += d0 * d0;
   double fit, sig, mn, ssd;
   bool   fl;
   return ComputeZ(sy, sxy, syy, y, sd, sdd, z_reg, z_sma, fit, sig, fl, mn, ssd);
}


//====================================================================
// 🕒 SESSION (เวลาเปิด / ปิดตลาดรายสัปดาห์)
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

bool LocateBlockAt(datetime t_now, datetime &open_t, datetime &close_t) {
   MqlDateTime dt;
   TimeToStruct(t_now, dt);
   datetime week_start = t_now - (datetime)(dt.day_of_week * DAY_SEC + dt.hour * 3600 + dt.min * 60 + dt.sec);
   long t = (long)(t_now - week_start);

   for(int i = 0; i < g_block_count; i++) {
      long s = g_blocks[i].s, e = g_blocks[i].e;
      if(t >= s && t < e) {
         open_t  = week_start + (datetime)s;
         close_t = week_start + (datetime)e;
         return true;
      }
      if(t + WEEK_SEC >= s && t + WEEK_SEC < e) {   // ช่วงที่เริ่มสัปดาห์ก่อนแล้วลากข้ามมา
         open_t  = week_start + (datetime)(s - WEEK_SEC);
         close_t = week_start + (datetime)(e - WEEK_SEC);
         return true;
      }
   }
   return false;
}

bool LocateBlock(datetime now) {
   if(g_blk_valid && now >= g_blk_open && now < g_blk_close) return true;
   g_blk_valid = LocateBlockAt(now, g_blk_open, g_blk_close);
   return g_blk_valid;
}

int GetTimeStateAt(datetime t) {
   if(!g_session_ok || g_always_open) return TS_OPEN;
   datetime o, c;
   if(!LocateBlockAt(t, o, c)) return TS_CLOSED;
   if(t >= c - (datetime)(InpCloseBeforeClose_Min * 60)) return TS_CLOSING;
   if(t >= c - (datetime)(InpNoTradeBeforeClose_Min * 60)) return TS_WAIT_CLOSE;
   if(t <  o + (datetime)(InpNoTradeAfterOpen_Min * 60)) return TS_WAIT_OPEN;
   return TS_OPEN;
}

datetime ForceCloseTimeAt(datetime t) {
   if(!g_session_ok || g_always_open) return 0;
   datetime o, c;
   if(!LocateBlockAt(t, o, c)) return 0;
   return c - (datetime)(InpCloseBeforeClose_Min * 60);
}

int GetTimeState(datetime now) {
   if(!g_session_ok || g_always_open) return TS_OPEN;
   if(!LocateBlock(now)) return TS_CLOSED;
   if(now >= g_blk_close - (datetime)(InpCloseBeforeClose_Min * 60)) return TS_CLOSING;
   if(now >= g_blk_close - (datetime)(InpNoTradeBeforeClose_Min * 60)) return TS_WAIT_CLOSE;
   if(now <  g_blk_open  + (datetime)(InpNoTradeAfterOpen_Min * 60)) return TS_WAIT_OPEN;
   return TS_OPEN;
}

string TimeStateText(int ts, datetime now) {
   if(!g_session_ok)  return "⚠️ ไม่มีข้อมูล Session (ไม่กรองเวลา)";
   if(g_always_open)  return "ตลาดเปิดตลอด (ไม่กรองเวลา)";
   switch(ts) {
      case TS_OPEN:
         return "✅ เทรดได้ | อีก " + FormatDuration((long)(g_blk_close - (datetime)(MathMax(InpNoTradeBeforeClose_Min, InpCloseBeforeClose_Min) * 60) - now)) + " จะห้ามเข้าไม้ก่อนปิดสัปดาห์";
      case TS_WAIT_CLOSE:
         return "⏳ ห้ามเข้า (ใกล้ตลาดปิดสัปดาห์) | อีก " + FormatDuration((long)(g_blk_close - (datetime)(InpCloseBeforeClose_Min * 60) - now)) + " จะบังคับปิดทุกไม้";
      case TS_WAIT_OPEN:
         return "⏳ ห้ามเข้า (ชั่วโมงแรกหลังเปิดสัปดาห์) | อีก " + FormatDuration((long)(g_blk_open + (datetime)(InpNoTradeAfterOpen_Min * 60) - now));
      case TS_CLOSING:
         return "🛑 ช่วงบังคับปิดก่อนตลาดปิด | ตลาดปิดในอีก " + FormatDuration((long)(g_blk_close - now));
   }
   return "💤 ตลาดปิด";
}

string EntryBlockReason(int ts, double bid, double ask) {
   if(ts == TS_WAIT_OPEN)  return "หลังตลาดเปิดสัปดาห์";
   if(ts == TS_WAIT_CLOSE) return "ก่อนตลาดปิดสัปดาห์";
   if(ts != TS_OPEN) return "เวลาตลาด";
   double sp = PriceToPts(ask - bid);
   if(sp > InpMaxSpread_Pts) return StringFormat("สเปรด %.0f > %.0f จุด", sp, InpMaxSpread_Pts);
   return "";
}

bool TradeAllowed() {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
}


//====================================================================
// 🎯 SIGNAL (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
void CtxReset(Ctx &c) {
   c.ready = false; c.bar = 0; c.zc.ok = false;
   c.open = 0.0; c.hi = 0.0; c.lo = 0.0;
   c.p_open = 0.0; c.p_high = 0.0; c.p_low = 0.0; c.p_close = 0.0; c.p_zhi = 0.0; c.p_zlo = 0.0;
   c.zok = false; c.zr = 0.0; c.zs = 0.0;
   for(int k = 0; k < 4; k++) c.done[k] = false;
   for(int s = 0; s < 2; s++) { c.sb[s] = false; c.sb_cancel[s] = false; c.sb_last_new[s] = 0; }
}

// แท่งใหม่: cl[0..n-1] = ราคาปิด n แท่งที่ปิดแล้ว (cl[n-1] = แท่งปิดล่าสุด), prev = OHLC แท่งปิดล่าสุด
void CtxNewBar(Ctx &c, datetime bar, double open, const double &cl[], const MqlRates &prev) {
   CtxReset(c);
   c.bar    = bar;
   c.open   = open;
   c.p_open = prev.open; c.p_high = prev.high; c.p_low = prev.low; c.p_close = prev.close;
   int    n = InpZ_Period;
   double zr, zs;
   c.p_zhi = ZForBarPrice(cl, n - 1, prev.high, zr, zs) ? MathMax(zr, zs) : 0.0;
   c.p_zlo = ZForBarPrice(cl, n - 1, prev.low,  zr, zs) ? MathMin(zr, zs) : 0.0;
   c.ready = BuildZCache(cl, c.zc);
}

// S2 ฝั่ง s (0 = สวนลงที่ไส้บน / 1 = สวนขึ้นที่ไส้ล่าง): แท่งปิดล่าสุดถึงเกณฑ์ไหม
bool S2Armed(const Ctx &c, int s) { return c.ready && ((s == 0) ? (c.p_zhi > InpS2_PrevZ) : (c.p_zlo < -InpS2_PrevZ)); }

// S2: อัปเดตสแตนบายด้วย tick (new_ext = tick นี้ทำ High (s=0) / Low (s=1) ใหม่ของแท่งปัจจุบัน)
void S2Track(Ctx &c, int s, double bid, long msc, bool new_ext) {
   if(!S2Armed(c, s) || c.sb_cancel[s]) return;
   if(s == 0) {
      if(c.hi > c.p_high) { c.sb_cancel[0] = true; c.sb[0] = false; return; }   // ทะลุ High แท่งปิดล่าสุด → ยกเลิก (ให้ S3)
      if(!c.sb[0]) { if(bid >= MathMax(c.p_open, c.p_close)) { c.sb[0] = true; c.sb_last_new[0] = msc; } return; }
   } else {
      if(c.lo < c.p_low) { c.sb_cancel[1] = true; c.sb[1] = false; return; }
      if(!c.sb[1]) { if(bid <= MathMin(c.p_open, c.p_close)) { c.sb[1] = true; c.sb_last_new[1] = msc; } return; }
   }
   if(new_ext) c.sb_last_new[s] = msc;
}

// tick ของแท่งปัจจุบัน: High / Low + Z สด + สแตนบาย S2
void CtxTick(Ctx &c, double bid, long msc) {
   bool nh = (c.hi <= 0.0 || bid > c.hi), nl = (c.lo <= 0.0 || bid < c.lo);
   if(nh) c.hi = bid;
   if(nl) c.lo = bid;
   double fit, sig, mn, ssd;
   bool   fl;
   c.zok = c.ready && ZAtPrice(c.zc, bid, c.zr, c.zs, fit, sig, fl, mn, ssd);
   S2Track(c, 0, bid, msc, nh);
   S2Track(c, 1, bid, msc, nl);
}

long S2Deadline(const Ctx &c, int s) { return c.sb_last_new[s] + (long)InpS2_NoNewSec * 1000; }

// S2 พร้อมยิงไหม → −1 SELL / +1 BUY / 0
int S2Ready(const Ctx &c, long msc) {
   if(c.sb[0] && !c.sb_cancel[0] && c.hi < c.p_high && msc >= S2Deadline(c, 0)) return -1;
   if(c.sb[1] && !c.sb_cancel[1] && c.lo > c.p_low  && msc >= S2Deadline(c, 1)) return  1;
   return 0;
}

double S2SL(const Ctx &c, int dir) { return (dir == -1) ? c.p_high + PtsToPrice(InpS2_Cut_Pts) : c.p_low - PtsToPrice(InpS2_Cut_Pts); }

// S1: Z สดเกินเกณฑ์ + ราคาอยู่ฝั่งที่วาง SL ที่ราคาเปิดแท่งได้ → +1 BUY / −1 SELL / 0
int S1Dir(const Ctx &c, double bid) {
   if(!c.zok) return 0;
   if(MathMax(c.zr, c.zs) >  InpS1_Z && bid > c.open) return  1;
   if(MathMin(c.zr, c.zs) < -InpS1_Z && bid < c.open) return -1;
   return 0;
}

// S3: แผนวาง Stop — k 0 = Buy Stop เหนือ High / 1 = Sell Stop ใต้ Low ของแท่งปิดล่าสุด
//   armed[k] = แท่งปิดล่าสุดถึงเกณฑ์, ok[k] = ราคายังไม่เกินจุดวาง (ไม่ gap) → คืนจำนวนฝั่งที่ถึงเกณฑ์
int S3Plan(const Ctx &c, double bid, double ask, double &px[], double &sl[], bool &armed[], bool &ok[]) {
   double d = PtsToPrice(InpS3_Dist_Pts);
   px[0] = c.p_high + d; sl[0] = c.p_open; armed[0] = c.ready && c.p_zhi >  InpS3_PrevZ; ok[0] = armed[0] && ask < px[0];
   px[1] = c.p_low  - d; sl[1] = c.p_open; armed[1] = c.ready && c.p_zlo < -InpS3_PrevZ; ok[1] = armed[1] && bid > px[1];
   return (armed[0] ? 1 : 0) + (armed[1] ? 1 : 0);
}

//====================================================================
// 🛡️ การจัดการไม้ (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
// ครึ่ง lot (ปัดลงตาม step) — 0 = แบ่งไม่ได้
double HalfLot(double lot) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   double half = MathFloor(lot / 2.0 / step + 1e-9) * step;
   if(half < vmin - 1e-9 || lot - half < vmin - 1e-9) return 0.0;
   return NormalizeDouble(half, 8);
}

bool SLBetter(int dir, double a, double b) { return (b <= 0.0) || ((dir == 1) ? (a > b + _Point * 0.5) : (a < b - _Point * 0.5)); }

// ตัดสินใจด้วยราคา tick: อัปเดตกำไรสูงสุด → ปิดครึ่ง (do_partial) / SL ใหม่ (new_sl, 0 = ไม่ขยับ) + ขั้น (new_stage)
//   เกราะ: กำไรสูงสุด ≥ InpLock_Trig_Pts → ทุน + InpLock_Pts | หลังปิดครึ่ง: ไล่จี้ห่างราคา InpTrail_Pts
void PDecide(PState &p, double bid, double ask, long msc, bool &do_partial, double &new_sl, int &new_stage) {
   double fav = (p.dir == 1) ? (bid - p.entry) : (p.entry - ask);
   if(fav > p.mfe) { p.mfe = fav; p.mfe_msc = msc; }
   do_partial = (!p.partial && InpPartial_Pts > 0.0 && fav >= PtsToPrice(InpPartial_Pts));
   new_sl = 0.0; new_stage = p.stage;
   double cand = 0.0;
   int    st   = p.stage;
   if(InpLock_Trig_Pts > 0.0 && p.mfe >= PtsToPrice(InpLock_Trig_Pts)) {
      cand = p.entry + p.dir * PtsToPrice(InpLock_Pts);
      st   = MathMax(st, 1);
   }
   if(p.partial || do_partial) {
      double t = (p.dir == 1) ? bid - PtsToPrice(InpTrail_Pts) : ask + PtsToPrice(InpTrail_Pts);
      if(cand == 0.0 || SLBetter(p.dir, t, cand)) { cand = t; st = 2; }
   }
   if(cand != 0.0 && SLBetter(p.dir, cand, p.sl)) { new_sl = cand; new_stage = st; }
}

// เหตุผลเมื่อชน SL ตามขั้นของไม้
int SLReason(const PState &p) { return (p.stage >= 2) ? RX_TRAIL : ((p.stage == 1) ? RX_LOCK : RX_SL); }

// เวลาตัดจบตามเวลา (InpExitBars > 0)
datetime ExitTimeOf(datetime opened) {
   return BarStartOf(opened) + (datetime)((long)(InpExitBars + 1) * PeriodSeconds(InpZ_Timeframe));
}

//====================================================================
// 💼 EA จริง: ส่งคำสั่ง
//====================================================================
bool IsOurPosition() { return PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol; }
bool IsOurOrder()    { return OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol; }

bool SysHasPosition(int sys) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t != 0 && IsOurPosition() && SysFromComment(PositionGetString(POSITION_COMMENT)) == sys) return true;
   }
   return false;
}

int OurPendingTotal() {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong t = OrderGetTicket(i); if(t != 0 && IsOurOrder()) n++; }
   return n;
}

// Market (dir = ทิศของไม้), SL เคารพ Stops Level
bool OpenMarket(int sys, int dir, double bid, double ask, double sl) {
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dir == 1) sl = MathMin(sl, bid - stops - _Point); else sl = MathMax(sl, ask + stops + _Point);
   sl = ND(sl);
   string cmt = InpOrderComment + " " + SysTag(sys);
   bool   ok  = (dir == 1) ? trade.Buy(InpLot, _Symbol, ask, sl, 0.0, cmt) : trade.Sell(InpLot, _Symbol, bid, sl, 0.0, cmt);
   uint   rc  = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      g_last_status = StringFormat("✅ %s %s %.2f @ %s | SL %s", SysTag(sys), (dir == 1 ? "BUY" : "SELL"), InpLot,
                                   DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(sl, _Digits));
      Print(g_last_status);
      return true;
   }
   g_last_status = StringFormat("❌ %s %s ไม่สำเร็จ: %u %s", SysTag(sys), (dir == 1 ? "BUY" : "SELL"), rc, trade.ResultRetcodeDescription());
   Print(g_last_status);
   return false;
}

// S3: Stop (dir = ทิศของไม้), หมดอายุเมื่อจบแท่ง (โบรกรองรับ = ใส่วันหมดอายุด้วย, EA ลบเองเสมอ)
bool PlaceStop(int dir, double price, double sl, datetime expire, double bid, double ask) {
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dir == 1 ? (price - ask < stops) : (bid - price < stops)) return false;
   price = ND(price); sl = ND(sl);
   string cmt = InpOrderComment + " " + SysTag(3);
   ENUM_ORDER_TYPE_TIME tt    = ORDER_TIME_GTC;
   datetime             exp_t = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0) { tt = ORDER_TIME_SPECIFIED; exp_t = expire; }
   bool ok = (dir == 1) ? trade.BuyStop(InpLot, price, _Symbol, sl, 0.0, tt, exp_t, cmt) : trade.SellStop(InpLot, price, _Symbol, sl, 0.0, tt, exp_t, cmt);
   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED)) {
      PrintFormat("✅ S3 วาง %s %.2f @ %s | SL %s (ราคาเปิดแท่งปิดล่าสุด)", (dir == 1 ? "BUY STOP" : "SELL STOP"), InpLot,
                  DoubleToString(price, _Digits), DoubleToString(sl, _Digits));
      return true;
   }
   PrintFormat("❌ S3 วาง %s ไม่สำเร็จ: %u %s", (dir == 1 ? "BUY STOP" : "SELL STOP"), rc, trade.ResultRetcodeDescription());
   return false;
}

void CloseAllPositions() {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(t != 0 && IsOurOrder() && !trade.OrderDelete(t))
         PrintFormat("❌ ลบออเดอร์รอ #%I64u ไม่สำเร็จ: %u %s", t, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      if(trade.PositionClose(t)) PrintFormat("🛑 ปิดไม้ #%I64u ก่อนตลาดปิดสัปดาห์", t);
      else PrintFormat("❌ ปิดไม้ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", t, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

//====================================================================
// 💼 EA จริง: บริบทแท่ง + สัญญาณ
//====================================================================
// แท่งปัจจุบันเปิด / ไม้ / Stop ของระบบไหนไปแล้วบ้าง (คืนค่าเมื่อเริ่ม EA / ขึ้นแท่งใหม่)
void LiveRestoreDone() {
   datetime bar = g_c.bar;
   if(HistorySelect(bar, ServerNow() + 60)) {
      for(int i = 0; i < HistoryDealsTotal(); i++) {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN || (datetime)HistoryDealGetInteger(d, DEAL_TIME) < bar) continue;
         int s = SysFromComment(HistoryDealGetString(d, DEAL_COMMENT));
         if(s > 0) g_c.done[s] = true;
      }
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(t != 0 && IsOurOrder() && (datetime)OrderGetInteger(ORDER_TIME_SETUP) >= bar) g_c.done[3] = true;
   }
}

// ขึ้นแท่งใหม่ (TF ของ Z) → สร้างบริบทใหม่จากแท่งที่ปิดแล้ว
void LiveCtxSync() {
   datetime bar0 = iTime(_Symbol, InpZ_Timeframe, 0);
   if(bar0 == 0 || bar0 == g_c.bar) return;
   int      n     = InpZ_Period;
   MqlRates r[];
   if(CopyRates(_Symbol, InpZ_Timeframe, 1, n, r) != n) return;   // ประวัติยังไม่พร้อม → ลองใหม่ tick ถัดไป
   double cl[];
   ArrayResize(cl, n);
   for(int i = 0; i < n; i++) cl[i] = r[i].close;
   bool first = (g_c.bar == 0);
   CtxNewBar(g_c, bar0, iOpen(_Symbol, InpZ_Timeframe, 0), cl, r[n - 1]);
   if(first) { g_c.hi = iHigh(_Symbol, InpZ_Timeframe, 0); g_c.lo = iLow(_Symbol, InpZ_Timeframe, 0); }   // เริ่ม EA กลางแท่ง
   LiveRestoreDone();
}

// สัญญาณของ EA จริง (เรียกทุก Tick + Timer) — ตัวกรองเวลาตลาด / สเปรด ตรวจตอนส่ง
void LiveSignals(int ts, double bid, double ask, long msc, bool tick) {
   if(!g_c.ready || !TradeAllowed()) return;
   datetime now = ServerNow();
   string   why = EntryBlockReason(ts, bid, ask);
   // S1 ตามน้ำสด (ต้องมี tick ใหม่ — Z สด)
   if(tick && g_en[1] && !g_c.done[1] && now >= g_next_try[1] && !SysHasPosition(1)) {
      int d = S1Dir(g_c, bid);
      if(d != 0 && why == "") {
         if(OpenMarket(1, d, bid, ask, g_c.open)) g_c.done[1] = true; else g_next_try[1] = now + 1;
      }
   }
   // S2 สวนที่ไส้
   if(g_en[2] && !g_c.done[2] && now >= g_next_try[2] && !SysHasPosition(2)) {
      int d = S2Ready(g_c, msc);
      if(d != 0) {
         if(why != "") { g_c.done[2] = true; g_last_status = "S2 ครบเวลาแต่ติด: " + why + " → ทิ้งสัญญาณของแท่งนี้"; }
         else if(OpenMarket(2, d, bid, ask, S2SL(g_c, d))) g_c.done[2] = true; else g_next_try[2] = now + 1;
      }
   }
   // S3 Stop ทะลุยอด
   if(g_en[3] && !g_c.done[3] && now >= g_next_try[3] && !SysHasPosition(3) && OurPendingTotal() == 0) {
      double px[2];
      double sl[2];
      bool   armed[2];
      bool   ok[2];
      if(S3Plan(g_c, bid, ask, px, sl, armed, ok) > 0 && why == "") {
         datetime expire = g_c.bar + (datetime)PeriodSeconds(InpZ_Timeframe);
         bool     placed = false;
         for(int k = 0; k < 2; k++) if(ok[k] && PlaceStop((k == 0) ? 1 : -1, px[k], sl[k], expire, bid, ask)) placed = true;
         if(placed || (!ok[0] && !ok[1])) g_c.done[3] = true;   // วางแล้ว / ราคาเกินจุดวางแล้ว (ข้าม)
         else g_next_try[3] = now + 1;
      }
   }
}

//====================================================================
// 💼 EA จริง: จัดการออเดอร์รอ + ไม้ (ทุก Tick + Timer 200 ms)
//====================================================================
int PosMonGet(ulong tk, int sys, int dir, double entry, double sl, double vol, long o_msc, long now_msc) {
   for(int i = ArraySize(g_pm) - 1; i >= 0; i--) if(g_pm[i].tk == tk) return i;
   int n = ArraySize(g_pm);
   ArrayResize(g_pm, n + 1);
   g_pm[n].tk          = tk;
   g_pm[n].ps.sys      = sys;
   g_pm[n].ps.dir      = dir;
   g_pm[n].ps.entry    = entry;
   g_pm[n].ps.sl       = sl;
   g_pm[n].ps.lot0     = MathMax(vol, InpLot);
   g_pm[n].ps.lot      = vol;
   g_pm[n].ps.mfe      = 0.0;
   g_pm[n].ps.mfe_msc  = now_msc;
   g_pm[n].ps.open_msc = o_msc;
   g_pm[n].ps.partial  = (vol < g_pm[n].ps.lot0 - 1e-9);   // เริ่ม EA ใหม่หลังปิดครึ่งแล้ว
   g_pm[n].ps.stage    = 0;
   if(sl > 0.0 && (dir == 1 ? sl > entry : sl < entry)) g_pm[n].ps.stage = g_pm[n].ps.partial ? 2 : 1;
   g_pm[n].last_mod    = 0;
   g_pm[n].next_try    = 0;
   return n;
}

void PosMonPrune() {
   int n = ArraySize(g_pm), w = 0;
   for(int i = 0; i < n; i++) if(PositionSelectByTicket(g_pm[i].tk)) g_pm[w++] = g_pm[i];
   if(w != n) ArrayResize(g_pm, w);
}

void ManageLive(datetime now, int ts, long now_msc) {
   // 1) S3 ออเดอร์รอ: จบแท่ง / อีกฝั่งถูกเกี่ยวแล้ว (OCO) / ช่วงห้ามเข้าก่อนปิดสัปดาห์ → ลบ
   if(now >= g_del_retry) {
      bool s3pos = SysHasPosition(3);
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong t = OrderGetTicket(i);
         if(t == 0 || !IsOurOrder()) continue;
         bool bar_end = (BarStartOf((datetime)OrderGetInteger(ORDER_TIME_SETUP)) != BarStartOf(now));
         if(!bar_end && !s3pos && ts != TS_WAIT_CLOSE && ts != TS_CLOSING) continue;
         if(trade.OrderDelete(t)) PrintFormat("🗑️ ลบ S3 #%I64u (%s)", t, bar_end ? "จบแท่งยังไม่ถูกเกี่ยว" : (s3pos ? "อีกฝั่งถูกเกี่ยวแล้ว" : "ช่วงห้ามเข้า"));
         else { g_del_retry = now + 1; PrintFormat("❌ ลบ S3 #%I64u ไม่สำเร็จ: %u %s", t, trade.ResultRetcode(), trade.ResultRetcodeDescription()); }
      }
   }
   // 2) ไม้: ตัดจบตามเวลา (ถ้าเปิด) → ปิดครึ่ง → เกราะ / ไล่จี้
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;
   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   PosMonPrune();
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      int    sys = SysFromComment(PositionGetString(POSITION_COMMENT));
      int    dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double sl  = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP), vol = PositionGetDouble(POSITION_VOLUME);
      int    k   = PosMonGet(t, sys, dir, PositionGetDouble(POSITION_PRICE_OPEN), sl, vol, PositionGetInteger(POSITION_TIME_MSC), now_msc);
      g_pm[k].ps.sl  = sl;
      g_pm[k].ps.lot = vol;
      bool   do_partial;
      double new_sl;
      int    new_stage;
      PDecide(g_pm[k].ps, bid, ask, now_msc, do_partial, new_sl, new_stage);
      if(now_msc < g_pm[k].next_try) continue;

      if(InpExitBars > 0 && now >= ExitTimeOf((datetime)PositionGetInteger(POSITION_TIME))) {
         if(trade.PositionClose(t)) PrintFormat("⏱️ #%I64u %s ตัดจบตามเวลา", t, SysTag(sys));
         else g_pm[k].next_try = now_msc + 300;
         continue;
      }
      if(do_partial) {
         double half = HalfLot(g_pm[k].ps.lot0);
         if(half > 0.0 && vol > half + 1e-9) {
            if(trade.PositionClosePartial(t, half)) {
               g_pm[k].ps.partial = true;
               g_last_status = StringFormat("✂️ #%I64u %s ปิดครึ่ง %.2f lot ที่กำไร %.0f จุด → ครึ่งที่เหลือไล่จี้ห่าง %.0f", t, SysTag(sys), half,
                                            PriceToPts(dir == 1 ? bid - g_pm[k].ps.entry : g_pm[k].ps.entry - ask), InpTrail_Pts);
               Print(g_last_status);
            } else { g_pm[k].next_try = now_msc + 300; PrintFormat("❌ ปิดครึ่ง #%I64u ไม่สำเร็จ: %u %s", t, trade.ResultRetcode(), trade.ResultRetcodeDescription()); continue; }
         }
         else g_pm[k].ps.partial = true;   // แบ่ง lot ไม่ได้ → ข้ามการปิดครึ่ง แต่ไล่จี้ต่อ
      }
      if(new_sl == 0.0) continue;
      new_sl = ND(new_sl);
      if(new_stage >= 2 && (now_msc - g_pm[k].last_mod < 1000 || !SLBetter(dir, new_sl, sl + dir * PtsToPrice(InpTrailStep_Pts) - dir * _Point))) continue;
      if(dir == 1 ? (bid - new_sl < stops) : (new_sl - ask < stops)) continue;          // Stops Level → รอ tick ถัดไป
      if(sl > 0.0 && (dir == 1 ? (bid - sl <= freeze) : (sl - ask <= freeze))) continue; // Freeze Level
      if(trade.PositionModify(t, new_sl, tp)) {
         if(new_stage != g_pm[k].ps.stage)
            PrintFormat("🛡️ #%I64u %s %s: SL → %s", t, SysTag(sys), (new_stage >= 2 ? "ไล่จี้" : "เกราะ"), DoubleToString(new_sl, _Digits));
         g_pm[k].ps.stage = new_stage;
         g_pm[k].ps.sl    = new_sl;
         g_pm[k].last_mod = now_msc;
      } else { g_pm[k].next_try = now_msc + 1000; PrintFormat("⚠️ ขยับ SL #%I64u ไม่สำเร็จ: %u %s", t, trade.ResultRetcode(), trade.ResultRetcodeDescription()); }
   }
}

//====================================================================
// 🧪 TICK REPLAY — เล่นซ้ำ tick จริงด้วยฟังก์ชันตัดสินใจชุดเดียวกับ EA จริง
//====================================================================
struct RTrade {
   int      sys, dir;
   long     msc_in;
   double   entry, sl0, lot0;
   PState   ps;
   double   p_zext;          // Z สุดขั้วของแท่งปิดล่าสุด (S2 / S3) หรือ Z สด (S1) ตอนเข้า
   double   zr_in, zs_in;
   long     partial_msc;
   double   partial_px, partial_usd;
   long     msc_out;
   double   p_out;
   int      reason;
   double   pnl_pts;         // จุดของส่วนที่เหลือ (หลังปิดครึ่ง)
   double   usd;             // รวมทั้งไม้ (ครึ่งแรก + ส่วนที่เหลือ)
   long     last_mod;        // ขยับ SL ไล่จี้ล่าสุด (msc) — จำกัดเหมือนไม้จริง
   bool     drawn_final;
};

struct RPend {               // S3 Stop จำลอง
   int      dir;
   double   price, sl;
   long     msc_set, exp_msc, msc_end;
   int      state;           // 0 รอ / 1 ถูกเกี่ยว / 2 หมดอายุ
   bool     drawn_final;
};

RTrade   g_rt[];
RPend    g_rpd[];
int      g_ro[4];             // ไม้ที่เปิดอยู่ของแต่ละระบบ (index ใน g_rt, −1 = ไม่มี)
Ctx      g_rc;
MqlRates g_rr[];
int      g_rp_b         = -1;
double   g_rp_bid = 0.0, g_rp_ask = 0.0;
long     g_rp_msc       = 0;
bool     g_rp_have      = false;
bool     g_rp_init      = false;
bool     g_rp_caught    = false;
long     g_rp_cursor    = 0;
int      g_rp_retry     = 0;
long     g_rp_fail_cur  = -1;
uint     g_rp_fail_ms   = 0;
int      g_rp_skip_n    = 0;
MqlTick  g_rp_buf[];
int      g_rp_buf_i     = 0;
int      g_rp_buf_n     = 0;
long     g_rp_buf_to    = 0;
long     g_rp_ticks     = 0;
int      g_rp_csv_rows  = -1;
string   g_rp_status    = "ยังไม่เริ่ม";
double   g_contract     = 100.0;

void ReplayReset() {
   ArrayResize(g_rt, 0); ArrayResize(g_rpd, 0); ArrayResize(g_rr, 0);
   for(int s = 0; s < 4; s++) g_ro[s] = -1;
   CtxReset(g_rc);
   g_rp_b = -1; g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_msc = 0;
   g_rp_have = false; g_rp_init = false; g_rp_caught = false; g_rp_cursor = 0; g_rp_retry = 0;
   g_rp_fail_cur = -1; g_rp_fail_ms = 0; g_rp_skip_n = 0;
   ArrayResize(g_rp_buf, 0); g_rp_buf_i = 0; g_rp_buf_n = 0; g_rp_buf_to = 0;
   g_rp_ticks = 0; g_rp_csv_rows = -1; g_rp_status = "ยังไม่เริ่ม";
}

bool ReplayLoadRates() {
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int count   = (InpReplayDays + 4) * per_day + InpZ_Period + 10;
   return CopyRates(_Symbol, InpZ_Timeframe, 0, count, g_rr) > InpZ_Period + 3;
}

// แท่งของเวลา t → สร้างบริบทใหม่เมื่อเปลี่ยนแท่ง
bool ReplayBarFor(datetime t) {
   int n = ArraySize(g_rr);
   if(n == 0) return false;
   if(t >= g_rr[n - 1].time + (datetime)PeriodSeconds(InpZ_Timeframe)) {
      if(!ReplayLoadRates()) return false;
      n = ArraySize(g_rr);
      g_rp_b = -1;
   }
   int b = g_rp_b;
   if(b < 0 || b >= n || g_rr[b].time > t || (b + 1 < n && g_rr[b + 1].time <= t)) {
      b = -1;
      for(int i = n - 1; i >= 0; i--) if(g_rr[i].time <= t) { b = i; break; }
   }
   if(b < InpZ_Period) return false;
   if(b == g_rp_b && g_rc.bar == g_rr[b].time) return true;
   g_rp_b = b;
   if(g_rc.bar != g_rr[b].time) {
      double cl[];
      ArrayResize(cl, InpZ_Period);
      for(int k = 0; k < InpZ_Period; k++) cl[k] = g_rr[b - InpZ_Period + k].close;
      CtxNewBar(g_rc, g_rr[b].time, g_rr[b].open, cl, g_rr[b - 1]);
   }
   return true;
}

void ReplayOpen(int sys, int dir, long msc, double price, double sl) {
   int i = ArraySize(g_rt);
   ArrayResize(g_rt, i + 1, 256);
   if(dir == 1) sl = MathMin(sl, price - _Point); else sl = MathMax(sl, price + _Point);
   g_rt[i].sys = sys; g_rt[i].dir = dir; g_rt[i].msc_in = msc;
   g_rt[i].entry = price; g_rt[i].sl0 = sl; g_rt[i].lot0 = InpLot;
   g_rt[i].ps.sys = sys; g_rt[i].ps.dir = dir; g_rt[i].ps.entry = price; g_rt[i].ps.sl = sl;
   g_rt[i].ps.lot0 = InpLot; g_rt[i].ps.lot = InpLot; g_rt[i].ps.mfe = 0.0; g_rt[i].ps.mfe_msc = msc;
   g_rt[i].ps.open_msc = msc; g_rt[i].ps.partial = false; g_rt[i].ps.stage = 0;
   g_rt[i].p_zext = (sys == 1) ? (dir == 1 ? MathMax(g_rc.zr, g_rc.zs) : MathMin(g_rc.zr, g_rc.zs))
                               : (((sys == 2) ? -dir : dir) == 1 ? g_rc.p_zhi : g_rc.p_zlo);
   g_rt[i].zr_in = g_rc.zr; g_rt[i].zs_in = g_rc.zs;
   g_rt[i].partial_msc = 0; g_rt[i].partial_px = 0.0; g_rt[i].partial_usd = 0.0;
   g_rt[i].msc_out = 0; g_rt[i].p_out = 0.0; g_rt[i].reason = RX_OPEN; g_rt[i].pnl_pts = 0.0; g_rt[i].usd = 0.0;
   g_rt[i].last_mod = 0; g_rt[i].drawn_final = false;
   g_ro[sys]          = i;
   g_rc.done[sys]     = true;
}

void ReplayClose(int sys, long msc, double price, int reason) {
   int i = g_ro[sys];
   if(i < 0) return;
   double diff = (g_rt[i].dir == 1) ? (price - g_rt[i].entry) : (g_rt[i].entry - price);
   g_rt[i].msc_out = msc; g_rt[i].p_out = price; g_rt[i].reason = reason;
   g_rt[i].pnl_pts = PriceToPts(diff);
   g_rt[i].usd     = g_rt[i].partial_usd + diff * g_rt[i].ps.lot * g_contract;
   g_ro[sys] = -1;
}

// เหตุการณ์ตามเวลาด้วยราคาของ tick ก่อนหน้า: S3 หมดอายุ / ปิดสัปดาห์ / ตัดจบตามเวลา / S2 ครบเวลาไม่มียอดใหม่
void ReplayTimeEvents(long msc) {
   if(!g_rp_have) return;
   for(int k = 0; k < ArraySize(g_rpd); k++)
      if(g_rpd[k].state == 0 && msc >= g_rpd[k].exp_msc) { g_rpd[k].state = 2; g_rpd[k].msc_end = g_rpd[k].exp_msc; }
   for(int s = 1; s <= 3; s++) {
      int i = g_ro[s];
      if(i < 0) continue;
      double   px = (g_rt[i].dir == 1) ? g_rp_bid : g_rp_ask;
      datetime fc = ForceCloseTimeAt((datetime)(g_rt[i].msc_in / 1000));
      if(fc > 0 && msc >= (long)fc * 1000) { ReplayClose(s, (long)fc * 1000, px, RX_WEEK); continue; }
      if(InpExitBars > 0) {
         long ex = (long)ExitTimeOf((datetime)(g_rt[i].msc_in / 1000)) * 1000;
         if(msc >= ex) ReplayClose(s, ex, px, RX_TIME);
      }
   }
   int ts = GetTimeStateAt((datetime)(msc / 1000));
   if(ts == TS_WAIT_CLOSE || ts == TS_CLOSING)   // ช่วงห้ามเข้าก่อนปิดสัปดาห์ → ลบ S3 ที่รอ (เหมือนไม้จริง)
      for(int k = 0; k < ArraySize(g_rpd); k++) if(g_rpd[k].state == 0) { g_rpd[k].state = 2; g_rpd[k].msc_end = msc; }
   if(g_en[2] && !g_rc.done[2] && g_ro[2] < 0 && g_rc.bar > 0) {
      long bar_end = ((long)g_rc.bar + PeriodSeconds(InpZ_Timeframe)) * 1000;   // ยิงได้ภายในแท่งของสัญญาณเท่านั้น
      int  d       = S2Ready(g_rc, MathMin(msc, bar_end - 1));
      if(d != 0) {
         long     fire = MathMax(S2Deadline(g_rc, d == -1 ? 0 : 1), g_rp_msc);
         datetime ft   = (datetime)(fire / 1000);
         if(EntryBlockReason(GetTimeStateAt(ft), g_rp_bid, g_rp_ask) == "") ReplayOpen(2, d, fire, (d == 1) ? g_rp_ask : g_rp_bid, S2SL(g_rc, d));
         else g_rc.done[2] = true;   // ติดตัวกรอง → ทิ้งสัญญาณของแท่งนี้
      }
   }
}

// ไม้ที่ถือ: SL → กำไรสูงสุด / ปิดครึ่ง / เกราะ / ไล่จี้ ด้วยราคา tick ปัจจุบัน (ฟังก์ชันเดียวกับ EA จริง)
void ReplayManage(long msc, double bid, double ask) {
   for(int s = 1; s <= 3; s++) {
      int i = g_ro[s];
      if(i < 0) continue;
      int    d  = g_rt[i].dir;
      double px = (d == 1) ? bid : ask;
      if(d == 1 ? (bid <= g_rt[i].ps.sl) : (ask >= g_rt[i].ps.sl)) { ReplayClose(s, msc, px, SLReason(g_rt[i].ps)); continue; }
      bool   do_partial;
      double new_sl;
      int    new_stage;
      PDecide(g_rt[i].ps, bid, ask, msc, do_partial, new_sl, new_stage);
      if(do_partial) {
         double half = HalfLot(g_rt[i].lot0);
         if(half > 0.0) {
            double diff = (d == 1) ? (bid - g_rt[i].entry) : (g_rt[i].entry - ask);
            g_rt[i].partial_msc = msc;
            g_rt[i].partial_px  = px;
            g_rt[i].partial_usd = diff * half * g_contract;
            g_rt[i].ps.lot      = g_rt[i].lot0 - half;
         }
         g_rt[i].ps.partial = true;
      }
      if(new_sl == 0.0) continue;
      if(new_stage >= 2 && (msc - g_rt[i].last_mod < 1000 || !SLBetter(d, new_sl, g_rt[i].ps.sl + d * PtsToPrice(InpTrailStep_Pts) - d * _Point))) continue;
      g_rt[i].ps.sl = new_sl; g_rt[i].ps.stage = new_stage; g_rt[i].last_mod = msc;
   }
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);
   ReplayTimeEvents(msc);                 // A) เหตุการณ์ตามเวลา (ราคาของ tick ก่อนหน้า)
   if(!ReplayBarFor(t)) return;           // B) แท่งของ tick นี้
   CtxTick(g_rc, bid, msc);               // C) High / Low / Z / สแตนบาย S2
   ReplayManage(msc, bid, ask);           // D) ไม้ที่ถือ
   for(int k = 0; k < ArraySize(g_rpd); k++) {   // E) S3 Stop ถูกเกี่ยว (ได้ราคาของ tick, ฝั่งที่เหลือยกเลิก)
      if(g_rpd[k].state != 0) continue;
      bool hit = (g_rpd[k].dir == 1) ? (ask >= g_rpd[k].price) : (bid <= g_rpd[k].price);
      if(!hit || g_ro[3] >= 0) continue;
      g_rpd[k].state = 1; g_rpd[k].msc_end = msc;
      ReplayOpen(3, g_rpd[k].dir, msc, (g_rpd[k].dir == 1) ? ask : bid, g_rpd[k].sl);
      for(int q = 0; q < ArraySize(g_rpd); q++) if(q != k && g_rpd[q].state == 0) { g_rpd[q].state = 2; g_rpd[q].msc_end = msc; }
   }
   string why = EntryBlockReason(GetTimeStateAt(t), bid, ask);
   if(g_en[1] && !g_rc.done[1] && g_ro[1] < 0 && why == "") {   // F) S1 ตามน้ำสด
      int d = S1Dir(g_rc, bid);
      if(d != 0) ReplayOpen(1, d, msc, (d == 1) ? ask : bid, g_rc.open);
   }
   if(g_en[3] && !g_rc.done[3] && g_ro[3] < 0 && why == "") {   // G) S3 วาง Stop
      double px[2];
      double sl[2];
      bool   armed[2];
      bool   ok[2];
      if(S3Plan(g_rc, bid, ask, px, sl, armed, ok) > 0) {
         long exp_ms = ((long)g_rc.bar + PeriodSeconds(InpZ_Timeframe)) * 1000;
         for(int k = 0; k < 2; k++) {
            if(!ok[k]) continue;
            int n = ArraySize(g_rpd);
            ArrayResize(g_rpd, n + 1, 64);
            g_rpd[n].dir = (k == 0) ? 1 : -1; g_rpd[n].price = px[k]; g_rpd[n].sl = sl[k];
            g_rpd[n].msc_set = msc; g_rpd[n].exp_msc = exp_ms; g_rpd[n].msc_end = 0; g_rpd[n].state = 0; g_rpd[n].drawn_final = false;
         }
         g_rc.done[3] = true;
      }
   }
   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc; g_rp_have = true; g_rp_ticks++;
}

string ReasonName(int r) {
   switch(r) {
      case RX_SL:    return "SL";
      case RX_LOCK:  return "เกราะ";
      case RX_TRAIL: return "ไล่จี้";
      case RX_WEEK:  return "ปิดสัปดาห์";
      case RX_TIME:  return "ตัดจบ";
   }
   return "ถืออยู่";
}

string ReasonCode(int r) {
   switch(r) {
      case RX_SL:    return "SL";
      case RX_LOCK:  return "LOCK";
      case RX_TRAIL: return "TRAIL";
      case RX_WEEK:  return "WEEKCLOSE";
      case RX_TIME:  return "TIME";
   }
   return "OPEN";
}

void DrawReplayTrade(int i) {
   datetime t_in = (datetime)(g_rt[i].msc_in / 1000);
   bool     open = (g_rt[i].reason == RX_OPEN);
   bool     buy  = (g_rt[i].dir == 1);
   color    clr  = SysColor(g_rt[i].sys);
   string   id   = IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
   string   na = OBJ_PREFIX + "RP_A_" + id, nl = OBJ_PREFIX + "RP_L_" + id, nt = OBJ_PREFIX + "RP_T_" + id, np = OBJ_PREFIX + "RP_P_" + id;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, buy ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, t_in, g_rt[i].entry);
      ObjectSetInteger(0, na, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }
   if(g_rt[i].partial_msc > 0 && ObjectFind(0, np) < 0) {   // จุดปิดครึ่ง
      ObjectCreate(0, np, OBJ_ARROW, 0, (datetime)(g_rt[i].partial_msc / 1000), g_rt[i].partial_px);
      ObjectSetInteger(0, np, OBJPROP_ARROWCODE, 159);
      ObjectSetInteger(0, np, OBJPROP_COLOR, InpClrWin);
      ObjectSetInteger(0, np, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, np, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  np, OBJPROP_TOOLTIP, StringFormat("%s ปิดครึ่ง @ %s ($%+.2f)", SysTag(g_rt[i].sys), DoubleToString(g_rt[i].partial_px, _Digits), g_rt[i].partial_usd));
   }
   if(!open) {
      datetime t_out = (datetime)(g_rt[i].msc_out / 1000);
      if(ObjectFind(0, nl) < 0) {
         ObjectCreate(0, nl, OBJ_TREND, 0, t_in, g_rt[i].entry, t_out, g_rt[i].p_out);
         ObjectSetInteger(0, nl, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, nl, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nl, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, nl, OBJPROP_COLOR, (g_rt[i].usd > 0.0) ? InpClrWin : InpClrLoss);
   }
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_in, g_rt[i].entry);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   string part = (g_rt[i].partial_msc > 0) ? StringFormat(" | ครึ่ง $%+.2f", g_rt[i].partial_usd) : "";
   string mfe  = StringFormat(" | สูงสุด %+.0f @%s", PriceToPts(g_rt[i].ps.mfe), ShortSec((g_rt[i].ps.mfe_msc - g_rt[i].msc_in) / 1000));
   ObjectSetInteger(0, nt, OBJPROP_COLOR, open ? clr : ((g_rt[i].usd > 0.0) ? InpClrWin : InpClrLoss));
   ObjectSetString(0, nt, OBJPROP_TEXT, open ? StringFormat("%s %s %.2f%s | ถืออยู่%s   ", SysTag(g_rt[i].sys), (buy ? "B" : "S"), g_rt[i].lot0, part, mfe)
                                              : StringFormat("%s %s %.2f%s | %s $%+.2f%s   ", SysTag(g_rt[i].sys), (buy ? "B" : "S"), g_rt[i].lot0, part,
                                                             ReasonName(g_rt[i].reason), g_rt[i].usd, mfe));
   string tip = StringFormat("จำลอง %s %s %.2f @ %s (%s) | SL แรก %s | Z ตอนเข้า R %+.2f / S %+.2f | Z อ้างอิง %+.2f",
                             SysTag(g_rt[i].sys), (buy ? "BUY" : "SELL"), g_rt[i].lot0, DoubleToString(g_rt[i].entry, _Digits),
                             TimeToString(t_in, TIME_DATE|TIME_SECONDS), DoubleToString(g_rt[i].sl0, _Digits), g_rt[i].zr_in, g_rt[i].zs_in, g_rt[i].p_zext);
   if(!open)
      tip += StringFormat("\nออก %s @ %s (%s) | ส่วนที่เหลือ %+.0f จุด | รวม $%+.2f | กำไรสูงสุด %+.0f (ถึงหลังเข้า %s)",
                          ReasonName(g_rt[i].reason), DoubleToString(g_rt[i].p_out, _Digits), TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS),
                          g_rt[i].pnl_pts, g_rt[i].usd, PriceToPts(g_rt[i].ps.mfe), ShortSec((g_rt[i].ps.mfe_msc - g_rt[i].msc_in) / 1000));
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tip);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tip);
   if(!open) ObjectSetString(0, nl, OBJPROP_TOOLTIP, tip);
   g_rt[i].drawn_final = (!open && iBarShift(_Symbol, InpZ_Timeframe, t_in, false) > 0);
}

void DrawReplayPending(int k) {
   string   nm = OBJ_PREFIX + "RP_S_" + IntegerToString(g_rpd[k].msc_set) + "_" + IntegerToString(k);
   datetime t0 = (datetime)(g_rpd[k].msc_set / 1000);
   datetime t1 = (datetime)(((g_rpd[k].state == 0) ? g_rpd[k].exp_msc : g_rpd[k].msc_end) / 1000);
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_TREND, 0, t0, g_rpd[k].price, t1, g_rpd[k].price);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, nm, 1, t1, g_rpd[k].price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, (g_rpd[k].state == 2) ? clrDimGray : InpClrS3);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, StringFormat("S3 %s @ %s | SL %s | %s", (g_rpd[k].dir == 1 ? "BUY STOP" : "SELL STOP"),
                                                        DoubleToString(g_rpd[k].price, _Digits), DoubleToString(g_rpd[k].sl, _Digits),
                                                        (g_rpd[k].state == 0 ? "รอ" : (g_rpd[k].state == 1 ? "ถูกเกี่ยว" : "ไม่ถูกเกี่ยว / ยกเลิก"))));
   g_rpd[k].drawn_final = (g_rpd[k].state != 0);
}

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rt); i++)  if(!g_rt[i].drawn_final)  DrawReplayTrade(i);
   for(int k = 0; k < ArraySize(g_rpd); k++) if(!g_rpd[k].drawn_final) DrawReplayPending(k);
}

string ReplayCSVName() { return "7LZ3_Replay_" + _Symbol + ".csv"; }

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n[4];
   int    w[4];
   double u[4];
   ArrayInitialize(n, 0); ArrayInitialize(w, 0); ArrayInitialize(u, 0.0);
   int    rc[6];
   ArrayInitialize(rc, 0);
   double tot = 0.0, peak = 0.0, dd = 0.0;
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      int sy = g_rt[i].sys;
      n[sy]++; n[0]++; u[sy] += g_rt[i].usd; u[0] += g_rt[i].usd;
      if(g_rt[i].usd > 0.0) { w[sy]++; w[0]++; }
      rc[g_rt[i].reason]++;
      tot += g_rt[i].usd;
      if(tot > peak) peak = tot;
      if(tot - peak < dd) dd = tot - peak;
   }
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ | ชนะ %.0f%% | สุทธิ $%+.2f | DD $%.2f | SL %d เกราะ %d ไล่จี้ %d ตัดจบ %d ปิดสัปดาห์ %d",
                           InpReplayDays, g_rp_status, n[0], (n[0] > 0 ? 100.0 * w[0] / n[0] : 0.0), u[0], dd,
                           rc[RX_SL], rc[RX_LOCK], rc[RX_TRAIL], rc[RX_TIME], rc[RX_WEEK]);
   for(int k = 1; k <= 3; k++)
      s += StringFormat("%s%s %d ไม้ ชนะ %.0f%% $%+.2f", (k == 1 ? "\n   " : " | "), SysTag(k), n[k], (n[k] > 0 ? 100.0 * w[k] / n[k] : 0.0), u[k]);
   if(g_rp_skip_n > 0) s += StringFormat(" | ⚠️ ข้ามช่วงที่ดึง tick ไม่ได้ %d ช่วง", g_rp_skip_n);
   if(InpReplayCSV && g_rp_csv_rows >= 0) s += StringFormat("\n   📄 CSV: MQL5\\Files\\%s (%d ไม้)", ReplayCSVName(), g_rp_csv_rows);
   return s;
}

void ReplayWriteCSV(int done) {
   string fn = ReplayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "system,side,time_in,price_in,sl_init,sl_init_pts,lot,z_ref,z_reg_in,z_sma_in," +
                      "partial_time,partial_price,partial_usd,time_out,exit,exit_price,pnl_pts_rest,usd_total,profit_max_pts,profit_max_sec,hold_sec\r\n");
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      string ln = StringFormat("%s,%s,%s,%s,%s,%.0f,%.2f,%.3f,%.3f,%.3f,", SysTag(g_rt[i].sys), (g_rt[i].dir == 1 ? "BUY" : "SELL"),
                               TimeToString((datetime)(g_rt[i].msc_in / 1000), TIME_DATE|TIME_SECONDS), DoubleToString(g_rt[i].entry, _Digits),
                               DoubleToString(g_rt[i].sl0, _Digits), PriceToPts(MathAbs(g_rt[i].entry - g_rt[i].sl0)), g_rt[i].lot0,
                               g_rt[i].p_zext, g_rt[i].zr_in, g_rt[i].zs_in);
      ln += (g_rt[i].partial_msc > 0)
            ? StringFormat("%s,%s,%.2f,", TimeToString((datetime)(g_rt[i].partial_msc / 1000), TIME_DATE|TIME_SECONDS), DoubleToString(g_rt[i].partial_px, _Digits), g_rt[i].partial_usd)
            : ",,,";
      ln += StringFormat("%s,%s,%s,%.0f,%.2f,%.0f,%d,%d\r\n", TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS),
                         ReasonCode(g_rt[i].reason), DoubleToString(g_rt[i].p_out, _Digits), g_rt[i].pnl_pts, g_rt[i].usd,
                         PriceToPts(g_rt[i].ps.mfe), (int)((g_rt[i].ps.mfe_msc - g_rt[i].msc_in) / 1000), (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000));
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_rp_csv_rows < 0) PrintFormat("📄 บันทึกไม้จำลอง %d ไม้ ลง MQL5\\Files\\%s (อัปเดตเมื่อมีไม้ปิดเพิ่ม)", done, fn);
   g_rp_csv_rows = done;
}

// เรียกทุก 1 วินาที (นอกช่วงร้อน): โหลด tick ทีละช่วง (ครั้งแรก 12 ชม.) แล้วเล่นตามงบเวลา จนถึงปัจจุบัน แล้วต่อแบบสด
void ReplayStep() {
   if(!g_draw || !InpShowReplay) return;
   if(!g_rp_init) {
      if(!ReplayLoadRates()) { g_rp_status = "⏳ รอประวัติแท่ง"; return; }
      g_contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(g_contract <= 0.0) g_contract = 100.0;
      g_rp_cursor = ((long)TimeCurrent() - (long)InpReplayDays * DAY_SEC) * 1000;
      g_rp_init   = true;
   }
   long  now_msc = MathMax((long)TimeCurrent() * 1000 + 999, g_last_tick_msc);
   ulong t0      = GetMicrosecondCount();
   if(g_rp_buf_i >= g_rp_buf_n) {
      long chunk = g_rp_caught ? (now_msc - g_rp_cursor) : (long)DAY_SEC * 500;
      long to    = MathMin(g_rp_cursor + chunk, now_msc);
      if(to >= g_rp_cursor) {
         int got = CopyTicksRange(_Symbol, g_rp_buf, COPY_TICKS_INFO, (ulong)g_rp_cursor, (ulong)to);
         if(got < 0) {
            int err = GetLastError();
            if(g_rp_fail_cur != g_rp_cursor) { g_rp_fail_cur = g_rp_cursor; g_rp_fail_ms = GetTickCount(); }
            uint waited = (GetTickCount() - g_rp_fail_ms) / 1000;
            if(g_rp_caught || waited < (uint)RP_SKIP_SEC) { g_rp_status = StringFormat("⏳ กำลังโหลด tick (error %d, รอมา %d วิ)", err, (int)waited); return; }
            g_rp_skip_n++;
            PrintFormat("⚠️ Tick Replay: ดึง tick ช่วง %s ไม่สำเร็จเกิน %d วิ (error %d) → ข้ามช่วงนี้", TimeToString((datetime)(g_rp_cursor / 1000)), RP_SKIP_SEC, err);
            g_rp_cursor = to + 1; g_rp_fail_cur = -1;
            return;
         }
         g_rp_fail_cur = -1;
         if(got == 0 && !g_rp_caught && g_rp_retry < 3 && GetTimeStateAt((datetime)((g_rp_cursor + to) / 2000)) != TS_CLOSED) { g_rp_retry++; return; }
         g_rp_retry  = 0;
         g_rp_buf_n  = got; g_rp_buf_i = 0; g_rp_buf_to = to;
         if(got > 0)           g_rp_cursor = (long)g_rp_buf[got - 1].time_msc + 1;
         else if(!g_rp_caught) g_rp_cursor = to + 1;
      }
   }
   while(g_rp_buf_i < g_rp_buf_n) {
      ReplayTick(g_rp_buf[g_rp_buf_i++]);
      if((g_rp_buf_i & 255) == 0 && GetMicrosecondCount() - t0 > (ulong)RP_BUDGET_US) break;
   }
   if(!g_rp_caught && g_rp_buf_i >= g_rp_buf_n && g_rp_buf_to >= now_msc - 2000) g_rp_caught = true;
   if(g_rp_caught) ReplayTimeEvents(now_msc);
   g_rp_status = g_rp_caught ? StringFormat("✅ ครบแล้ว + เดินต่อแบบสด (%I64d ticks)", g_rp_ticks)
                             : StringFormat("⏳ กำลังเล่นซ้ำ ถึง %s (%I64d ticks)", TimeToString((datetime)(g_rp_msc / 1000), TIME_DATE|TIME_MINUTES), g_rp_ticks);
   ReplayDraw();
   if(InpReplayCSV && g_rp_caught) {
      int done = 0;
      for(int i = 0; i < ArraySize(g_rt); i++) if(g_rt[i].reason != RX_OPEN) done++;
      if(done != g_rp_csv_rows) ReplayWriteCSV(done);
   }
}

//====================================================================
// 🎨 DISPLAY
//====================================================================
void SetRect(string name, datetime t0, double p0, datetime t1, double p1, color clr, string tip) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t0, p0, t1, p1);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, name, 0, t0, p0);
   ObjectMove(0, name, 1, t1, p1);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

void SetSeg(string name, datetime t0, datetime t1, double px, color clr, ENUM_LINE_STYLE st, string tip) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TREND, 0, t0, px, t1, px);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, name, 0, t0, px);
   ObjectMove(0, name, 1, t1, px);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

// โซนไส้ S2 / ระดับ SL ของ S2 / ระดับ Stop ของ S3 บนแท่งปัจจุบัน (ไม่ถึงเกณฑ์ = ลบ)
void DrawLevels() {
   string zu = OBJ_PREFIX + "ZONE_U", zd = OBJ_PREFIX + "ZONE_D", cu = OBJ_PREFIX + "CUT_U", cd = OBJ_PREFIX + "CUT_D";
   string su = OBJ_PREFIX + "S3_U", sd = OBJ_PREFIX + "S3_D";
   if(!g_draw || !InpShowLevels || !g_c.ready) { ObjectsDeleteAll(0, OBJ_PREFIX + "ZONE_"); ObjectsDeleteAll(0, OBJ_PREFIX + "CUT_"); ObjectsDeleteAll(0, OBJ_PREFIX + "S3_"); return; }
   long     per = PeriodSeconds(InpZ_Timeframe);
   datetime t0  = g_c.bar - (datetime)per, t1 = g_c.bar + (datetime)per;
   if(S2Armed(g_c, 0)) {
      SetRect(zu, t0, MathMax(g_c.p_open, g_c.p_close), t1, g_c.p_high, g_c.sb[0] ? InpClrZoneOn : InpClrZone,
              StringFormat("S2 โซนไส้บน (Z ที่ High %+.2f)%s", g_c.p_zhi, g_c.sb_cancel[0] ? " — ยกเลิก (ทะลุยอด)" : (g_c.sb[0] ? " — สแตนบาย" : "")));
      SetSeg(cu, g_c.bar, t1, S2SL(g_c, -1), InpClrLevel, STYLE_DOT, "S2 SELL: SL = High แท่งปิดล่าสุด + " + DoubleToString(InpS2_Cut_Pts, 0));
   } else { ObjectDelete(0, zu); ObjectDelete(0, cu); }
   if(S2Armed(g_c, 1)) {
      SetRect(zd, t0, g_c.p_low, t1, MathMin(g_c.p_open, g_c.p_close), g_c.sb[1] ? InpClrZoneOn : InpClrZone,
              StringFormat("S2 โซนไส้ล่าง (Z ที่ Low %+.2f)%s", g_c.p_zlo, g_c.sb_cancel[1] ? " — ยกเลิก (ทะลุยอด)" : (g_c.sb[1] ? " — สแตนบาย" : "")));
      SetSeg(cd, g_c.bar, t1, S2SL(g_c, 1), InpClrLevel, STYLE_DOT, "S2 BUY: SL = Low แท่งปิดล่าสุด − " + DoubleToString(InpS2_Cut_Pts, 0));
   } else { ObjectDelete(0, zd); ObjectDelete(0, cd); }
   double px[2];
   double sl[2];
   bool   armed[2];
   bool   ok[2];
   S3Plan(g_c, g_c.hi, g_c.hi, px, sl, armed, ok);
   if(armed[0]) SetSeg(su, g_c.bar, t1, px[0], InpClrS3, STYLE_DASH, StringFormat("S3 Buy Stop %s | SL %s", DoubleToString(px[0], _Digits), DoubleToString(sl[0], _Digits)));
   else ObjectDelete(0, su);
   if(armed[1]) SetSeg(sd, g_c.bar, t1, px[1], InpClrS3, STYLE_DASH, StringFormat("S3 Sell Stop %s | SL %s", DoubleToString(px[1], _Digits), DoubleToString(sl[1], _Digits)));
   else ObjectDelete(0, sd);
}

string S2Text(long msc) {
   string s = "";
   for(int k = 0; k < 2; k++) {
      if(!S2Armed(g_c, k)) continue;
      string side = (k == 0) ? "SELL ไส้บน" : "BUY ไส้ล่าง";
      if(g_c.sb_cancel[k])  s += side + " ยกเลิก (ทะลุยอด → S3) ";
      else if(g_c.sb[k])    s += StringFormat("%s สแตนบาย ยิงในอีก %.1f วิ ", side, MathMax(0.0, (S2Deadline(g_c, k) - msc) / 1000.0));
      else                  s += side + " รอราคาเข้าโซน ";
   }
   return (s == "") ? "แท่งปิดล่าสุดไม่ถึงเกณฑ์" : s;
}

string PositionLines(double bid, double ask) {
   string out = "";
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !IsOurOrder()) continue;
      out += StringFormat("\n  ⏳ #%I64u S3 %s @ %s | SL %s", t, (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP ? "BUY STOP" : "SELL STOP"),
                          DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), _Digits), DoubleToString(OrderGetDouble(ORDER_SL), _Digits));
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      bool   buy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      string st   = "";
      for(int k = ArraySize(g_pm) - 1; k >= 0; k--)
         if(g_pm[k].tk == t) { st = StringFormat(" | สูงสุด %+.0f | %s", PriceToPts(g_pm[k].ps.mfe), (g_pm[k].ps.stage >= 2 ? "ไล่จี้" : (g_pm[k].ps.stage == 1 ? "เกราะ" : "SL แรก"))); break; }
      out += StringFormat("\n  #%I64u %s %s %.2f @ %s | กำไร %+.0f จุด | SL %s%s", t, SysTag(SysFromComment(PositionGetString(POSITION_COMMENT))),
                          (buy ? "BUY" : "SELL"), PositionGetDouble(POSITION_VOLUME), DoubleToString(open, _Digits),
                          buy ? PriceToPts(bid - open) : PriceToPts(open - ask), DoubleToString(PositionGetDouble(POSITION_SL), _Digits), st);
   }
   return out;
}

void UpdateDashboard(int ts, datetime now, long msc) {
   if(!g_draw || !InpShowDashboard) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   string msg = StringFormat("=== 📊 7-Lines Z3 EA v1.00 (%s S1 Z>%.1f | %s S2 Z แท่งก่อน>%.1f ไส้ %d วิ SL ยอด±%.0f | %s S3 Z แท่งก่อน>%.1f Stop ±%.0f SL เปิดแท่งก่อน | Lot %.2f | เกราะ %.0f→+%.0f | ครึ่ง %.0f ไล่จี้ %.0f) ===\n",
                             (g_en[1] ? "✅" : "⛔"), InpS1_Z, (g_en[2] ? "✅" : "⛔"), InpS2_PrevZ, InpS2_NoNewSec, InpS2_Cut_Pts,
                             (g_en[3] ? "✅" : "⛔"), InpS3_PrevZ, InpS3_Dist_Pts, InpLot, InpLock_Trig_Pts, InpLock_Pts, InpPartial_Pts, InpTrail_Pts);
   msg += g_c.zok ? StringFormat("Z สด : R %+.2f | S %+.2f | เปิดแท่ง %s\n", g_c.zr, g_c.zs, DoubleToString(g_c.open, _Digits)) : "Z สด : รอข้อมูล\n";
   msg += StringFormat("แท่งปิดล่าสุด : O %s H %s L %s C %s | Z ที่ High %+.2f / ที่ Low %+.2f\n",
                       DoubleToString(g_c.p_open, _Digits), DoubleToString(g_c.p_high, _Digits), DoubleToString(g_c.p_low, _Digits),
                       DoubleToString(g_c.p_close, _Digits), g_c.p_zhi, g_c.p_zlo);
   msg += StringFormat("S1 : %s | S2 : %s | S3 : %s\n", (g_c.done[1] ? "เปิดแล้วแท่งนี้" : "รอ"), S2Text(msc), (g_c.done[3] ? "วาง / ข้ามแล้วแท่งนี้" : "รอ"));
   msg += StringFormat("สเปรด %.0f / %.0f จุด | เวลาตลาด : %s\n", PriceToPts(ask - bid), InpMaxSpread_Pts, TimeStateText(ts, now));
   msg += "สถานะล่าสุด : " + g_last_status;
   if(InpShowReplay) msg += "\n" + ReplayStatsText();
   msg += PositionLines(bid, ask);
   if(msg != g_last_comment) { g_last_comment = msg; Comment(msg); }
}

//====================================================================
// 🔘 ปุ่ม S1-S3
//====================================================================
string SysGVName(int s) { return StringFormat("7LZ3_%s_%I64d_S%d", _Symbol, InpMagic, s); }

void SysEnableInit() {
   int  r       = UninitializeReason();
   bool restore = (r == REASON_CHARTCHANGE || r == REASON_RECOMPILE || r == REASON_ACCOUNT);
   g_en[0] = false; g_en[1] = InpEnableS1; g_en[2] = InpEnableS2; g_en[3] = InpEnableS3;
   for(int s = 1; s <= 3; s++) {
      if(restore && GlobalVariableCheck(SysGVName(s))) g_en[s] = (GlobalVariableGet(SysGVName(s)) > 0.5);
      GlobalVariableSet(SysGVName(s), g_en[s] ? 1.0 : 0.0);
   }
}

void DrawButtons() {
   if(!g_draw) return;
   for(int s = 1; s <= 3; s++) {
      string nm = BTN_PREFIX + IntegerToString(s);
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10 + (s - 1) * 76);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 34);
         ObjectSetInteger(0, nm, OBJPROP_XSIZE, 70);
         ObjectSetInteger(0, nm, OBJPROP_YSIZE, 22);
         ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
      ObjectSetString(0,  nm, OBJPROP_TEXT, SysTag(s) + (g_en[s] ? " ON" : " OFF"));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, g_en[s] ? clrSeaGreen : clrDimGray);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP, StringFormat("คลิกเพื่อ%s %s (Tick Replay จะเล่นซ้ำใหม่)", (g_en[s] ? "ปิด" : "เปิด"), SysTag(s)));
   }
}

void ToggleSys(int s) {
   if(s < 1 || s > 3) return;
   g_en[s] = !g_en[s];
   GlobalVariableSet(SysGVName(s), g_en[s] ? 1.0 : 0.0);
   ObjectsDeleteAll(0, OBJ_PREFIX + "RP_");
   ReplayReset();
   g_last_status = StringFormat("%s %s (ปุ่ม) — Tick Replay เริ่มเล่นซ้ำใหม่", SysTag(s), (g_en[s] ? "เปิด" : "ปิด"));
   DrawButtons();
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
int OnInit() {
   if(InpZ_Period < 3 || InpReplayDays < 1 || InpReplayDays > 60 || InpLot <= 0.0 || InpS2_NoNewSec < 0 ||
      InpS2_Cut_Pts <= 0.0 || InpS3_Dist_Pts <= 0.0 || InpLock_Trig_Pts < 0.0 || (InpLock_Trig_Pts > 0.0 && InpLock_Pts >= InpLock_Trig_Pts) ||
      InpPartial_Pts < 0.0 || InpTrail_Pts <= 0.0 || InpExitBars < 0) {
      Print("❌ ค่า input ไม่ถูกต้อง (Period ≥ 3, วัน Replay 1-60, Lot > 0, ระยะต่างๆ > 0, เกราะล็อกน้อยกว่ากำไรที่สั่งขยับ)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Print("❌ EA นี้ต้องใช้บัญชีแบบ Hedging (ถือหลายระบบพร้อมกัน)");
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
   CtxReset(g_c);
   for(int s = 0; s < 4; s++) g_next_try[s] = 0;
   g_last_tick_msc = 0; g_tick_local = 0; g_del_retry = 0; g_heavy_ms = 0; g_blk_valid = false;
   g_last_comment = ""; g_last_status = "เริ่มทำงาน";
   ArrayResize(g_pm, 0);
   ReplayReset();
   SysEnableInit();
   ObjectsDeleteAll(0, OBJ_PREFIX);
   DrawButtons();
   EventSetMillisecondTimer(200);   // งานเทรดทุก 200 ms, งานแสดงผลทุก 1 วินาที
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
}

void OnTick() {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk) || tk.bid <= 0.0 || tk.ask <= 0.0) return;
   g_last_tick_msc = (long)tk.time_msc;
   g_tick_local    = GetTickCount();
   LiveCtxSync();
   if(g_c.ready) CtxTick(g_c, tk.bid, g_last_tick_msc);
   // งานเทรดก่อน → แสดงผลทีหลัง (OnTimer)
   datetime now = ServerNow();
   int      ts  = GetTimeState(now);
   if(ts == TS_CLOSING) { CloseAllPositions(); return; }
   if(ts != TS_CLOSED) ManageLive(now, ts, g_last_tick_msc);
   LiveSignals(ts, tk.bid, tk.ask, g_last_tick_msc, true);
}

void OnTimer() {
   datetime now = ServerNow();
   long     msc = NowMsc();
   int      ts  = GetTimeState(now);
   double   bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   // 1. งานเทรดทุก 200 ms (แม้ไม่มี Tick): บังคับปิด / จัดการไม้ / ลบ Stop / S2 ครบเวลา
   if(ts == TS_CLOSING) CloseAllPositions();
   else if(bid > 0.0 && ask > 0.0) {
      LiveCtxSync();
      if(ts != TS_CLOSED) ManageLive(now, ts, msc);
      LiveSignals(ts, bid, ask, msc, false);
   }
   // 2. แสดงผลทุก 1 วินาที — ช่วงร้อน (S2 สแตนบาย) ข้าม Tick Replay
   if(!g_draw || GetTickCount() - g_heavy_ms < 1000) return;
   g_heavy_ms = GetTickCount();
   if(!(g_c.sb[0] || g_c.sb[1])) ReplayStep();
   DrawLevels();
   UpdateDashboard(ts, now, msc);
   ChartRedraw(0);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BTN_PREFIX) == 0) {
      ToggleSys((int)StringToInteger(StringSubstr(sparam, StringLen(BTN_PREFIX))));
      ChartRedraw(0);
   }
}

// ดีลเปิดของ EA → นับว่าระบบนั้นเปิดแล้วในแท่งนี้ (กันเปิดซ้ำแม้ผลส่งคำสั่งมาช้า)
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;
   int s = SysFromComment(HistoryDealGetString(trans.deal, DEAL_COMMENT));
   if(s > 0 && (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME) >= g_c.bar) g_c.done[s] = true;
}
//+------------------------------------------------------------------+
