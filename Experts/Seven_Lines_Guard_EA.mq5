//+------------------------------------------------------------------+
//|                                         Seven_Lines_Guard_EA.mq5 |
//|   Guard EA for XAUUSD: บริหารความเสี่ยงรายวัน + Hit & Run 4 ระบบ    |
//+------------------------------------------------------------------+
//
// 🎯 เป้าหมาย: กำไรวันละ InpDailyTarget_USD (ค่าเริ่มต้น 30$) — เน้นบริหารความเสี่ยง ไม่ได้เน้นทายทิศ (ประวัติอยู่ใน README.md)
//
// 🛡️ บริหารรายวัน (กฎเดียวคุมทุกระบบ)
//  • กรณีแย่สุดของวัน = กำไรที่ปิดแล้ววันนี้ + ผลถ้าไม้ที่ถือชน SL → ต้องไม่ต่ำกว่าพื้น
//      ก่อนถึงเป้า: พื้น = −InpDailyMaxLoss_USD | ถึงเป้าแล้ว: พื้น = เป้า + InpFloorKeepPct% ของส่วนเกินสูงสุด (ขยับขึ้นอย่างเดียว)
//  • เสี่ยงต่อไม้ = min(InpRiskPct% ของทุน, กำไรปิดแล้ว − พื้น) → lot = เสี่ยง ÷ (ระยะ SL + สเปรด) ปัดลงเป็นเลขคู่ (แบ่งครึ่งได้), สูงสุด InpMaxLot
//  • ล็อกเป้า: ปิดแล้ว + กำไรลอย ≥ เป้า + InpTargetLockBuf_USD → ขยับ SL ไม้ที่ถือ ให้ชน SL แล้วยังได้ ≥ เป้า
//  • แพ้ติด InpMaxConsecLoss ชุด → หยุดทั้งวัน | ถึงเป้าแล้ว: หยุด หรือ เทรดต่อด้วยกำไรส่วนเกิน (InpAfterTarget)
//
// ⚡ ระบบเข้า Hit & Run (สมมาตรทั้งสองทิศ, ถือได้ทีละ 1 ชุด, แต่ละระบบครั้งเดียวต่อแท่ง M15)
//  • H1 สวนยอดพุ่ง   : Z ตัวใดตัวหนึ่ง > 3.0 → ไม่มียอดใหม่ 2 วิ → Market สวน, SL = ยอดแท่ง ± 500
//  • H2 ระเบิดจุดวิกฤติ: Z ทั้งสองตัว > 2.5 → Buy Stop / Sell Stop ห่าง ±1,000 (OCO, อายุ 5 นาที), SL 1,500
//  • H3 สวนที่ไส้     : แท่งปิดล่าสุด Z ที่ยอด > 2.5 → ราคาเข้าไส้ → ไม่มียอดใหม่ 10 วิ + ยอดแท่งปัจจุบัน < ยอดแท่งก่อน → Market สวน, SL = ยอดแท่งก่อน ± 500
//  • H4 ตามแรงกระชาก : Z > 2.0 + ทำยอดใหม่ ≥ 4 ครั้งใน 60 วิ (K2) → Market ตามน้ำ, SL = ราคาต่ำสุด / สูงสุดของ 60 วิล่าสุด
//  • ระยะ SL ถูกบีบให้อยู่ใน 1,000–3,000 จุด
//
// 📋 ทางออก: เปิด 2 ไม้ครึ่ง lot — A: TP1 = 1R ที่โบรก | B: TP2 = 3R ที่โบรก
//    ราคาถึง 1R → SL ของ B ไปทุน +200 → ไล่จี้ห่าง 1,500 | ถือได้นานสุด 10 นาที | ตัดเร็ว: 15 วิ กำไรสูงสุดยังไม่ถึง 500 → ปิดทั้งชุด
//
// 🧪 Tick Replay: จำลองทั้งระบบเข้าและการบริหารรายวันจาก tick จริง → มาร์ก + สรุป + CSV รายชุด / รายวัน (MQL5/Files)
//
#property copyright   "Commander's Quant System"
#property version     "1.00"
#property description "บริหารความเสี่ยงรายวัน (เป้า 30$) + Hit & Run 4 ระบบจากค่า Z + แบ่งไม้ครึ่ง สำหรับ XAUUSD (บัญชี Hedging)"

#include <Trade\Trade.mqh>

enum ENUM_AFTER_TARGET {
   AT_STOP     = 0,   // หยุดเทรดทั้งวัน
   AT_CONTINUE = 1    // เทรดต่อด้วยกำไรส่วนเกิน (กำไรต้องยังเกินเป้า)
};

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z / นับแท่ง
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z_reg ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. บริหารรายวัน ==="
input double            InpDailyTarget_USD   = 30.0;       // 🎯 เป้ากำไรต่อวัน ($)
input ENUM_AFTER_TARGET InpAfterTarget       = AT_CONTINUE; // ถึงเป้าแล้ว: หยุด / เทรดต่อด้วยกำไรส่วนเกิน
input double            InpFloorKeepPct      = 50.0;       // ถึงเป้าแล้ว: พื้น = เป้า + กี่ % ของส่วนเกินสูงสุด
input double            InpTargetLockBuf_USD = 5.0;        // ล็อกเป้า: ปิดแล้ว + ลอย ≥ เป้า + ค่านี้ → ขยับ SL ให้ชนแล้วยังได้ ≥ เป้า
input double            InpRiskPct           = 5.0;        // เสี่ยงต่อชุด (% ของทุนปัจจุบัน)
input double            InpDailyMaxLoss_USD  = 15.0;       // ขาดทุนสูงสุดต่อวัน ($)
input int               InpMaxConsecLoss     = 3;          // แพ้ติดกันกี่ชุด → หยุดทั้งวัน (0 = ปิด)
input double            InpMaxLot            = 0.04;       // Lot สูงสุดต่อชุด (A + B)
input double            InpMinFreeMarginPct  = 50.0;       // หลังเปิดไม้ Free Margin ต้องเหลืออย่างน้อยกี่ % ของ Equity

input group "=== 3. ระบบเข้า Hit & Run (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ) ==="
input bool            InpEnableH1          = true;       // H1 สวนยอดพุ่ง
input double          InpH1_Z              = 3.00;       // H1: Z_reg หรือ Z_SMA > ค่านี้
input int             InpH1_Sec            = 2;          // H1: ไม่มียอดใหม่ครบกี่วินาที → ยิง
input bool            InpEnableH2          = true;       // H2 ระเบิดที่จุดวิกฤติ
input double          InpH2_Z              = 2.50;       // H2: Z_reg และ Z_SMA ทั้งคู่ > ค่านี้
input double          InpH2_Dist_Pts       = 1000.0;     // H2: Stop ห่างราคาตอนสัญญาณฝั่งละกี่จุด
input double          InpH2_SL_Pts         = 1500.0;     // H2: SL ห่างราคา Stop กี่จุด
input int             InpH2_Expire_Min     = 5;          // H2: Stop ไม่ถูกเกี่ยวภายในกี่นาที → ลบ
input bool            InpEnableH3          = true;       // H3 สวนที่ไส้แท่งปิดล่าสุด
input double          InpH3_PrevZ          = 2.50;       // H3: แท่งปิดล่าสุด Z ตัวใดตัวหนึ่งที่ High (SELL) / Low (BUY) > ค่านี้
input int             InpH3_Sec            = 10;         // H3: ไม่มียอดใหม่ครบกี่วินาที → ยิง
input bool            InpEnableH4          = true;       // H4 ตามแรงกระชาก
input double          InpH4_Z              = 2.00;       // H4: Z_reg หรือ Z_SMA > ค่านี้ (ทิศตามน้ำ)
input int             InpH4_K2             = 4;          // H4: ทำยอดใหม่ของแท่งอย่างน้อยกี่ครั้ง
input int             InpH4_WinSec         = 60;         // H4: ภายในกี่วินาทีล่าสุด (= ช่วงหา SL ด้วย, สูงสุด 60)
input double          InpSLBuf_Pts         = 500.0;      // H1 / H3: SL = ยอด ± กี่จุด
input double          InpMinSL_Pts         = 1000.0;     // ระยะ SL ต่ำสุด (ใกล้กว่านี้ → ขยายเป็นค่านี้)
input double          InpMaxSL_Pts         = 3000.0;     // ระยะ SL สูงสุด (ไกลกว่านี้ → บีบเป็นค่านี้)

input group "=== 4. ทางออก (ไม้ A / B ครึ่ง lot) ==="
input double          InpTP1_R             = 1.0;        // ไม้ A: TP1 = กี่ R (R = ระยะ SL)
input double          InpTP2_R             = 3.0;        // ไม้ B: TP2 = กี่ R (0 = ไม่มี)
input double          InpBE_Pts            = 200.0;      // ราคาถึง TP1 → SL ของ B ไปที่ทุน + กี่จุด
input double          InpTrail_Pts         = 1500.0;     // หลังย้ายทุน: B ไล่จี้ห่างราคากี่จุด
input double          InpTrailStep_Pts     = 100.0;      // ไล่จี้ (ไม้จริง): ขยับเมื่อดีขึ้นอย่างน้อยกี่จุด (ไม่เกิน 1 ครั้ง/วินาที)
input int             InpMaxHold_Min       = 10;         // ถือชุดได้นานสุดกี่นาที (0 = ไม่จำกัด)
input int             InpFastCut_Sec       = 15;         // ตัดเร็ว: ครบกี่วินาทีหลังเข้า ...
input double          InpFastCut_Pts       = 500.0;      // ... กำไรสูงสุดยังไม่ถึงกี่จุด → ปิดทั้งชุด (0 = ปิด)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880400;     // Magic Number (แยกจาก EA อื่น)
input string          InpOrderComment      = "7L-GD";    // คอมเมนต์ออเดอร์ (ต่อท้ายด้วย H1-H4 + A / B)

input group "=== 5. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 400.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpNoTradeBeforeClose_Min = 60;    // ห้ามเข้าไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ + ลบออเดอร์รอก่อนตลาดปิดสัปดาห์ (นาที)

input group "=== 6. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowLevels        = true;       // แสดงโซนไส้ของ H3 บนแท่งปัจจุบัน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองย้อนหลังจาก tick จริง
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input double          InpReplayBalance     = 100.0;      // Tick Replay: ทุนเริ่มต้นจำลอง ($)
input bool            InpReplayCSV         = true;       // Tick Replay: บันทึก CSV รายชุด + รายวัน (MQL5/Files)

input group "=== 7. สี ==="
input color           InpClrH1             = clrOrange;         // ชุด H1
input color           InpClrH2             = clrMagenta;        // ชุด H2
input color           InpClrH3             = clrGold;           // ชุด H3
input color           InpClrH4             = clrDeepSkyBlue;    // ชุด H4
input color           InpClrWin            = clrLimeGreen;      // ชุดกำไร
input color           InpClrLoss           = clrTomato;         // ชุดขาดทุน
input color           InpClrZone           = C'70,55,25';       // โซนไส้ (H3) รอราคา
input color           InpClrZoneOn         = C'120,70,20';      // โซนไส้ (H3) กำลังสแตนบาย

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define TS_OPEN       0
#define TS_WAIT_OPEN  1
#define TS_CLOSING    2
#define TS_CLOSED     3
#define TS_WAIT_CLOSE 4

#define RX_OPEN   0
#define RX_SL     1   // ชน SL แรก
#define RX_TP1    2   // ไม้ A ถึง TP1
#define RX_TP2    3   // ไม้ B ถึง TP2
#define RX_BE     4   // ไม้ B ชน SL ที่ทุน
#define RX_TRAIL  5   // ไม้ B ชนโล่ไล่จี้
#define RX_LOCK   6   // ชน SL ล็อกเป้า
#define RX_FAST   7   // ตัดเร็ว
#define RX_TIME   8   // ครบเวลาถือ
#define RX_FLOOR  9   // กำไรรวมแตะพื้น → ปิดฉุกเฉิน
#define RX_WEEK   10  // บังคับปิดก่อนตลาดปิดสัปดาห์
#define RX_N      11

#define K2_CAP    32

const string OBJ_PREFIX    = "7LGD_";
const string BTN_PREFIX    = "7LGD_BTN_H";
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
   bool     done[5];        // ระบบ 1-4 เปิด / วางแล้วในแท่งนี้
   bool     h1_arm[2];      // H1: [0] = Z พุ่งขึ้นเกินเกณฑ์ (รอ SELL) / [1] = พุ่งลง (รอ BUY)
   long     h1_last[2];     // H1: เวลายอดใหม่ล่าสุดหลังถึงเกณฑ์
   bool     sb[2];          // H3 สแตนบาย: [0] = ไส้บน (SELL) / [1] = ไส้ล่าง (BUY)
   bool     sb_cancel[2];   // H3: ราคาทะลุยอดแท่งปิดล่าสุดแล้ว → ยกเลิกทั้งแท่ง
   long     sb_last_new[2]; // H3: เวลายอดใหม่ล่าสุดระหว่างสแตนบาย
   long     nh_t[K2_CAP];   // K2: เวลาที่ทำ High ใหม่ของแท่ง (วงแหวน)
   int      nh_i;
   long     nl_t[K2_CAP];   // K2: เวลาที่ทำ Low ใหม่ของแท่ง
   int      nl_i;
};

// ราคาสูง / ต่ำสุดรายวินาที ย้อนหลัง 64 วินาที (หา SL ของ H4, ข้ามแท่งได้)
struct Win60 {
   long   id[64];
   double lo[64];
   double hi[64];
};

// สถานะชุด (A + B) ที่ใช้ตัดสินใจร่วมกันทั้ง EA จริงและ Tick Replay
struct SetSt {
   int    sys, dir;         // ระบบ 1-4, ทิศ +1 BUY / −1 SELL
   double entry, R;         // ราคาเข้า, ระยะ SL (ราคา)
   long   open_msc;
   double mfe;              // กำไรสูงสุด (ราคา)
   long   mfe_msc;
   int    stage;            // 0 = SL แรก / 1 = B ที่ทุน / 2 = B ไล่จี้
   bool   fc_done;          // ตรวจตัดเร็วแล้ว
   bool   lock;             // ล็อกเป้าทำงานแล้ว
};

// สถานะรายวัน (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct DaySt {
   datetime day;
   double   closed;         // กำไรที่ปิดแล้ววันนี้ ($)
   double   peak, low;      // สูงสุด / ต่ำสุดของกำไรปิดแล้ว
   int      consec;         // แพ้ติดกัน (ชุด)
   int      sets, wins;
};

CTrade    trade;
double    g_pmult        = 1.0;
double    g_vpp          = 100.0;     // มูลค่า ($) ต่อราคา 1.0 ต่อ 1 lot
bool      g_draw         = true;
bool      g_en[5];                    // เปิดใช้ระบบ 1-4 (ปุ่มบนกราฟ)

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
Win60     g_w;
DaySt     g_day;
bool      g_day_dirty     = true;
datetime  g_day_check     = 0;
long      g_last_tick_msc = 0;
uint      g_tick_local    = 0;        // GetTickCount ตอน tick ล่าสุด (นาฬิกาเสริม)
datetime  g_next_try[5];              // ส่งคำสั่งของระบบไม่สำเร็จ → ลองใหม่หลังเวลานี้
datetime  g_del_retry     = 0;
uint      g_heavy_ms      = 0;
string    g_last_status   = "เริ่มทำงาน";
string    g_last_comment  = "";

struct LiveSet {
   bool   on;
   ulong  tk[2];            // ตั๋วของไม้ A / B (0 = ไม่มี)
   SetSt  ps;
   long   last_mod;         // ขยับ SL ไล่จี้ล่าสุด (msc)
   long   next_try;         // สั่งไม่สำเร็จ → ลองใหม่หลังเวลานี้ (msc)
};
LiveSet   g_set;

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


datetime DayStartOf(datetime t) { return (datetime)((long)t - (long)t % DAY_SEC); }

// เวลาตอนนี้ (msc, นาฬิกาเซิร์ฟเวอร์): เวลา tick ล่าสุด + เวลาที่ผ่านไปตามนาฬิกาในเครื่อง — แม่นแม้ tick ห่าง
long NowMsc() {
   long srv = (long)ServerNow() * 1000;
   if(g_last_tick_msc <= 0) return srv;
   return MathMax(g_last_tick_msc + (long)(GetTickCount() - g_tick_local), srv);
}

string SysTag(int sys) { return "H" + IntegerToString(sys); }

int SysFromComment(string c) {
   for(int s = 1; s <= 4; s++)
      if(StringFind(c, InpOrderComment + " " + SysTag(s)) >= 0) return s;
   return 0;
}

// ไม้ A = 0 / B = 1 จากคอมเมนต์ (−1 = ไม่รู้)
int LegFromComment(string c) {
   int n = StringLen(c);
   if(n < 2 || StringFind(c, InpOrderComment) < 0) return -1;
   string last = StringSubstr(c, n - 2);
   if(last == " A") return 0;
   if(last == " B") return 1;
   return -1;
}

color SysColor(int sys) {
   switch(sys) {
      case 1: return InpClrH1;
      case 2: return InpClrH2;
      case 3: return InpClrH3;
   }
   return InpClrH4;
}

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
   for(int k = 0; k < 5; k++) c.done[k] = false;
   for(int s = 0; s < 2; s++) {
      c.h1_arm[s] = false; c.h1_last[s] = 0;
      c.sb[s] = false; c.sb_cancel[s] = false; c.sb_last_new[s] = 0;
   }
   for(int k = 0; k < K2_CAP; k++) { c.nh_t[k] = 0; c.nl_t[k] = 0; }
   c.nh_i = 0; c.nl_i = 0;
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

// H3 ฝั่ง s (0 = ไส้บน → SELL / 1 = ไส้ล่าง → BUY): แท่งปิดล่าสุดถึงเกณฑ์ไหม
bool H3Armed(const Ctx &c, int s) { return c.ready && ((s == 0) ? (c.p_zhi > InpH3_PrevZ) : (c.p_zlo < -InpH3_PrevZ)); }

// H3: อัปเดตสแตนบายด้วย tick (new_ext = tick นี้ทำ High (s=0) / Low (s=1) ใหม่ของแท่งปัจจุบัน)
void H3Track(Ctx &c, int s, double bid, long msc, bool new_ext) {
   if(!H3Armed(c, s) || c.sb_cancel[s]) return;
   if(s == 0) {
      if(c.hi > c.p_high) { c.sb_cancel[0] = true; c.sb[0] = false; return; }   // ทะลุ High แท่งปิดล่าสุด → ยกเลิก
      if(!c.sb[0]) { if(bid >= MathMax(c.p_open, c.p_close)) { c.sb[0] = true; c.sb_last_new[0] = msc; } return; }
   } else {
      if(c.lo < c.p_low) { c.sb_cancel[1] = true; c.sb[1] = false; return; }
      if(!c.sb[1]) { if(bid <= MathMin(c.p_open, c.p_close)) { c.sb[1] = true; c.sb_last_new[1] = msc; } return; }
   }
   if(new_ext) c.sb_last_new[s] = msc;
}

// tick ของแท่งปัจจุบัน: High / Low + Z สด + H1 / H3 / K2
void CtxTick(Ctx &c, double bid, long msc) {
   bool nh = (c.hi <= 0.0 || bid > c.hi), nl = (c.lo <= 0.0 || bid < c.lo);
   if(nh) { c.hi = bid; c.nh_t[c.nh_i] = msc; c.nh_i = (c.nh_i + 1) % K2_CAP; }
   if(nl) { c.lo = bid; c.nl_t[c.nl_i] = msc; c.nl_i = (c.nl_i + 1) % K2_CAP; }
   double fit, sig, mn, ssd;
   bool   fl;
   c.zok = c.ready && ZAtPrice(c.zc, bid, c.zr, c.zs, fit, sig, fl, mn, ssd);
   for(int s = 0; s < 2; s++) {
      bool spike = c.zok && ((s == 0) ? (MathMax(c.zr, c.zs) > InpH1_Z) : (MathMin(c.zr, c.zs) < -InpH1_Z));
      if(!c.h1_arm[s]) { if(spike) { c.h1_arm[s] = true; c.h1_last[s] = msc; } }
      else if((s == 0) ? nh : nl) c.h1_last[s] = msc;
   }
   H3Track(c, 0, bid, msc, nh);
   H3Track(c, 1, bid, msc, nl);
}

long H1Deadline(const Ctx &c, int s) { return c.h1_last[s] + (long)InpH1_Sec * 1000; }
long H3Deadline(const Ctx &c, int s) { return c.sb_last_new[s] + (long)InpH3_Sec * 1000; }

// H1 พร้อมยิงไหม → −1 SELL (หลังพุ่งขึ้น) / +1 BUY / 0
int H1Ready(const Ctx &c, long msc) {
   if(c.h1_arm[0] && msc >= H1Deadline(c, 0)) return -1;
   if(c.h1_arm[1] && msc >= H1Deadline(c, 1)) return  1;
   return 0;
}

// H3 พร้อมยิงไหม → −1 SELL / +1 BUY / 0
int H3Ready(const Ctx &c, long msc) {
   if(c.sb[0] && !c.sb_cancel[0] && c.hi < c.p_high && msc >= H3Deadline(c, 0)) return -1;
   if(c.sb[1] && !c.sb_cancel[1] && c.lo > c.p_low  && msc >= H3Deadline(c, 1)) return  1;
   return 0;
}

// K2: จำนวนครั้งที่ทำ High (s=0) / Low (s=1) ใหม่ของแท่งภายใน InpH4_WinSec วินาทีล่าสุด
int K2Count(const Ctx &c, int s, long msc) {
   long from = msc - (long)InpH4_WinSec * 1000;
   int  n    = 0;
   for(int k = 0; k < K2_CAP; k++) {
      long t = (s == 0) ? c.nh_t[k] : c.nl_t[k];
      if(t > 0 && t >= from) n++;
   }
   return n;
}

// H4: Z ตามน้ำเกินเกณฑ์ + ทำยอดใหม่ถี่ → +1 BUY / −1 SELL / 0
int H4Dir(const Ctx &c, long msc) {
   if(!c.zok) return 0;
   if(MathMax(c.zr, c.zs) >  InpH4_Z && K2Count(c, 0, msc) >= InpH4_K2) return  1;
   if(MathMin(c.zr, c.zs) < -InpH4_Z && K2Count(c, 1, msc) >= InpH4_K2) return -1;
   return 0;
}

// H2: Z ทั้งสองตัวเกินเกณฑ์ฝั่งเดียวกัน → +1 (ขึ้น) / −1 (ลง) / 0
int H2Sig(const Ctx &c) {
   if(!c.zok) return 0;
   if(c.zr >  InpH2_Z && c.zs >  InpH2_Z) return  1;
   if(c.zr < -InpH2_Z && c.zs < -InpH2_Z) return -1;
   return 0;
}

// SL ดิบของแต่ละระบบ (ก่อนบีบระยะ)
double H1SL(const Ctx &c, int dir) { return (dir == -1) ? c.hi + PtsToPrice(InpSLBuf_Pts) : c.lo - PtsToPrice(InpSLBuf_Pts); }
double H3SL(const Ctx &c, int dir) { return (dir == -1) ? c.p_high + PtsToPrice(InpSLBuf_Pts) : c.p_low - PtsToPrice(InpSLBuf_Pts); }

void WinReset(Win60 &w) { for(int i = 0; i < 64; i++) { w.id[i] = -1; w.lo[i] = 0.0; w.hi[i] = 0.0; } }

void WinAdd(Win60 &w, long msc, double bid) {
   long s = msc / 1000;
   int  i = (int)(s % 64);
   if(w.id[i] != s) { w.id[i] = s; w.lo[i] = bid; w.hi[i] = bid; return; }
   if(bid < w.lo[i]) w.lo[i] = bid;
   if(bid > w.hi[i]) w.hi[i] = bid;
}

// H4: SL = ต่ำสุด (BUY) / สูงสุด (SELL) ของ InpH4_WinSec วินาทีล่าสุด
double H4SL(const Win60 &w, long msc, int dir, double px) {
   long   s1 = msc / 1000, s0 = s1 - MathMin(60, MathMax(1, InpH4_WinSec));
   double v  = px;
   for(int i = 0; i < 64; i++) {
      if(w.id[i] < s0 || w.id[i] > s1) continue;
      if(dir == 1) v = MathMin(v, w.lo[i]); else v = MathMax(v, w.hi[i]);
   }
   return v;
}

// ระยะ SL (ราคา) บีบให้อยู่ใน InpMinSL_Pts – InpMaxSL_Pts
double ClampR(int dir, double entry, double sl) {
   double r = (dir == 1) ? (entry - sl) : (sl - entry);
   return MathMax(PtsToPrice(InpMinSL_Pts), MathMin(PtsToPrice(InpMaxSL_Pts), r));
}

//====================================================================
// 🛡️ บริหารรายวัน (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
void DayReset(DaySt &d, datetime day) { d.day = day; d.closed = 0.0; d.peak = 0.0; d.low = 0.0; d.consec = 0; d.sets = 0; d.wins = 0; }

void DayAddLeg(DaySt &d, double usd) {
   d.closed += usd;
   if(d.closed > d.peak) d.peak = d.closed;
   if(d.closed < d.low)  d.low  = d.closed;
}

void DaySetClosed(DaySt &d, double usd) {
   d.sets++;
   if(usd < 0.0) d.consec++;
   else { d.consec = 0; if(usd > 0.0) d.wins++; }
}

bool   DayReached(const DaySt &d) { return d.peak >= InpDailyTarget_USD; }
// พื้นของกรณีแย่สุด: ก่อนถึงเป้า = −ขาดทุนสูงสุด / ถึงเป้าแล้ว = เป้า + % ของส่วนเกินสูงสุด
double DayFloor(const DaySt &d)   { return DayReached(d) ? InpDailyTarget_USD + InpFloorKeepPct / 100.0 * (d.peak - InpDailyTarget_USD) : -InpDailyMaxLoss_USD; }
// พื้นของการล็อกเป้า: ก่อนถึงเป้า = เป้า / ถึงเป้าแล้ว = พื้นปัจจุบัน
double LockFloor(const DaySt &d)  { return DayReached(d) ? DayFloor(d) : InpDailyTarget_USD; }

// เข้าชุดใหม่ได้ไหม → "" = ได้ + งบความเสี่ยง ($)
string DayGate(const DaySt &d, double balance, double &budget) {
   budget = 0.0;
   if(InpMaxConsecLoss > 0 && d.consec >= InpMaxConsecLoss) return StringFormat("แพ้ติด %d ชุด → หยุดวันนี้", d.consec);
   if(DayReached(d) && InpAfterTarget == AT_STOP) return "ถึงเป้าแล้ว → หยุดวันนี้";
   double room = d.closed - DayFloor(d);
   budget = MathMin(MathMax(0.0, balance) * InpRiskPct / 100.0, room);
   if(budget <= 0.0) return DayReached(d) ? "กำไรเหลือเหนือพื้นไม่พอ" : "ชนขาดทุนสูงสุดของวัน";
   return "";
}

string DayPhase(const DaySt &d) {
   if(InpMaxConsecLoss > 0 && d.consec >= InpMaxConsecLoss) return "⛔ หยุด (แพ้ติด)";
   if(DayReached(d)) return (InpAfterTarget == AT_STOP) ? "🏁 ถึงเป้า → หยุด" : "🏁 ถึงเป้า → เทรดต่อด้วยกำไรส่วนเกิน";
   if(d.closed <= -InpDailyMaxLoss_USD + 0.01) return "⛔ หยุด (ชนขาดทุนสูงสุด)";
   return "🎯 ล่าเป้า";
}

// lot รวม (A + B) จากงบความเสี่ยงและระยะ SL รวมสเปรด — ปัดลงให้แบ่งครึ่งได้, 0 = งบไม่พอ
double LotFor(double budget, double dist) {
   if(budget <= 0.0 || dist <= 0.0 || g_vpp <= 0.0) return 0.0;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   double half = MathFloor(budget / (dist * g_vpp) / 2.0 / step + 1e-9) * step;
   half = MathMin(half, MathFloor(InpMaxLot / 2.0 / step + 1e-9) * step);
   if(half < vmin - 1e-9) return 0.0;
   return NormalizeDouble(half * 2.0, 8);
}

// SL ล็อกเป้า: ชน SL แล้ว ปิดแล้ว + ผลของไม้ที่ถือ = floorv
double LockSL(int dir, double closed, double floorv, double lots, double entry) {
   if(lots <= 0.0 || g_vpp <= 0.0) return 0.0;
   return entry + dir * (floorv - closed) / (lots * g_vpp);
}

//====================================================================
// 📋 ทางออกของชุด (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
bool SLBetter(int dir, double a, double b) { return (b <= 0.0) || ((dir == 1) ? (a > b + _Point * 0.5) : (a < b - _Point * 0.5)); }

void SetMfe(SetSt &p, double bid, double ask, long msc) {
   double fav = (p.dir == 1) ? (bid - p.entry) : (p.entry - ask);
   if(fav > p.mfe) { p.mfe = fav; p.mfe_msc = msc; }
}

// ทางออกตามเวลา → RX_FAST / RX_TIME / 0 (ev_msc = เวลาที่เกิด)
int SetTimeExit(SetSt &p, long msc, long &ev_msc) {
   if(!p.fc_done && InpFastCut_Pts > 0.0) {
      long t = p.open_msc + (long)InpFastCut_Sec * 1000;
      if(msc >= t) {
         p.fc_done = true;
         if(p.mfe < PtsToPrice(InpFastCut_Pts)) { ev_msc = t; return RX_FAST; }
      }
   }
   if(InpMaxHold_Min > 0) {
      long t = p.open_msc + (long)InpMaxHold_Min * 60000;
      if(msc >= t) { ev_msc = t; return RX_TIME; }
   }
   return 0;
}

// SL เป้าหมายของไม้ B: ถึง TP1 → ทุน + InpBE_Pts → ไล่จี้ห่าง InpTrail_Pts (0 = ยังไม่ขยับ)
double SetBSL(const SetSt &p, double bid, double ask, int &stage) {
   stage = p.stage;
   if(p.stage == 0 && p.mfe < p.R * InpTP1_R - _Point * 0.5) return 0.0;
   double cand = p.entry + p.dir * PtsToPrice(InpBE_Pts);
   stage = MathMax(stage, 1);
   double t = (p.dir == 1) ? bid - PtsToPrice(InpTrail_Pts) : ask + PtsToPrice(InpTrail_Pts);
   if(SLBetter(p.dir, t, cand)) { cand = t; stage = 2; }
   return cand;
}

// เวลาสิ้นสุดของ H2 Stop
long H2ExpireMsc(long set_msc) { return set_msc + (long)InpH2_Expire_Min * 60000; }

//====================================================================
// 💼 EA จริง: สถานะรายวันจากประวัติดีล
//====================================================================
// สร้างสถานะวันนี้ใหม่จากดีลของ EA (ทนการรีสตาร์ท): ชุดจบ = ไม้ของ EA เหลือ 0
void LiveDayRebuild() {
   datetime d0 = DayStartOf(ServerNow());
   DayReset(g_day, d0);
   g_day_dirty = false;
   g_day_check = ServerNow();
   if(!HistorySelect(d0, ServerNow() + 60)) { g_day_dirty = true; return; }
   int    open  = 0;
   double start = 0.0;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      long   et  = HistoryDealGetInteger(d, DEAL_ENTRY);
      double pnl = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                   HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      if(et == DEAL_ENTRY_IN) {
         if(open == 0) start = g_day.closed;
         open++;
         if(pnl != 0.0) DayAddLeg(g_day, pnl);
      } else {
         DayAddLeg(g_day, pnl);
         open--;
         if(open <= 0) { open = 0; DaySetClosed(g_day, g_day.closed - start); start = g_day.closed; }
      }
   }
}

void LiveDaySync() {
   datetime now = ServerNow();
   if(g_day_dirty || DayStartOf(now) != g_day.day || now - g_day_check >= 10) LiveDayRebuild();
}

//====================================================================
// 💼 EA จริง: ส่งคำสั่ง
//====================================================================
bool IsOurPosition() { return PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol; }
bool IsOurOrder()    { return OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol; }

int OurPositionsTotal() {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong t = PositionGetTicket(i); if(t != 0 && IsOurPosition()) n++; }
   return n;
}

int OurPendingTotal() {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong t = OrderGetTicket(i); if(t != 0 && IsOurOrder()) n++; }
   return n;
}

// Margin พอไหม (หลังเปิด Free Margin ≥ InpMinFreeMarginPct% ของ Equity)
bool MarginOK(int dir, double lot, double price) {
   double m = 0.0;
   if(!OrderCalcMargin(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, price, m)) return true;   // คำนวณไม่ได้ → ให้โบรกตัดสิน
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (fm - m) >= eq * InpMinFreeMarginPct / 100.0;
}

// เปิดชุด Market (A: TP1, B: TP2) → 1 = สำเร็จ / 0 = ส่งไม่สำเร็จ (ลองใหม่) / −1 = ข้าม (งบ / margin / ระยะ)
int OpenSet(int sys, int dir, double bid, double ask, double sl_raw, double budget) {
   double entry = (dir == 1) ? ask : bid;
   double R     = ClampR(dir, entry, sl_raw);
   double lot   = LotFor(budget, R + (ask - bid));
   if(lot <= 0.0) { g_last_status = StringFormat("%s: งบ $%.2f ไม่พอเปิด 2 ไม้ครึ่ง (SL %.0f จุด) → ข้าม", SysTag(sys), budget, PriceToPts(R)); return -1; }
   if(!MarginOK(dir, lot, entry)) { g_last_status = StringFormat("%s: Margin ไม่พอสำหรับ %.2f lot → ข้าม", SysTag(sys), lot); return -1; }
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(R <= stops) { g_last_status = SysTag(sys) + ": ระยะ SL ใกล้กว่า Stops Level → ข้าม"; return -1; }
   double half = NormalizeDouble(lot / 2.0, 8);
   double sl   = ND(entry - dir * R);
   double tp1  = ND(entry + dir * R * InpTP1_R);
   double tp2  = (InpTP2_R > 0.0) ? ND(entry + dir * R * InpTP2_R) : 0.0;
   string ca   = InpOrderComment + " " + SysTag(sys) + " A", cb = InpOrderComment + " " + SysTag(sys) + " B";
   bool   okA  = (dir == 1) ? trade.Buy(half, _Symbol, ask, sl, tp1, ca) : trade.Sell(half, _Symbol, bid, sl, tp1, ca);
   uint   rc   = trade.ResultRetcode();
   if(!okA || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL)) {
      g_last_status = StringFormat("❌ %s %s ไม่สำเร็จ: %u %s", SysTag(sys), (dir == 1 ? "BUY" : "SELL"), rc, trade.ResultRetcodeDescription());
      Print(g_last_status);
      return 0;
   }
   double fill = trade.ResultPrice();
   bool   okB  = (dir == 1) ? trade.Buy(half, _Symbol, ask, sl, tp2, cb) : trade.Sell(half, _Symbol, bid, sl, tp2, cb);
   if(!okB) PrintFormat("⚠️ %s ไม้ B ไม่สำเร็จ: %u %s (ถือไม้ A อย่างเดียว)", SysTag(sys), trade.ResultRetcode(), trade.ResultRetcodeDescription());
   g_last_status = StringFormat("✅ %s %s %.2f+%.2f @ %s | SL %s (%.0f จุด, เสี่ยง $%.2f) | TP1 %s | TP2 %s", SysTag(sys), (dir == 1 ? "BUY" : "SELL"),
                                half, half, DoubleToString(fill, _Digits), DoubleToString(sl, _Digits), PriceToPts(R),
                                lot * (R + ask - bid) * g_vpp, DoubleToString(tp1, _Digits), DoubleToString(tp2, _Digits));
   Print(g_last_status);
   return 1;
}

// H2: Buy Stop + Sell Stop (ฝั่งละ 2 ไม้ A / B) → 1 / 0 / −1 เหมือน OpenSet
int PlaceStraddle(double bid, double ask, double budget, long now_msc) {
   double d     = PtsToPrice(InpH2_Dist_Pts), R = PtsToPrice(InpH2_SL_Pts);
   double lot   = LotFor(budget, R + (ask - bid));
   if(lot <= 0.0) { g_last_status = StringFormat("H2: งบ $%.2f ไม่พอเปิด 2 ไม้ครึ่ง → ข้าม", budget); return -1; }
   if(!MarginOK(1, lot, ask + d)) { g_last_status = StringFormat("H2: Margin ไม่พอสำหรับ %.2f lot → ข้าม", lot); return -1; }
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(d <= stops || R <= stops) { g_last_status = "H2: ระยะใกล้กว่า Stops Level → ข้าม"; return -1; }
   double half = NormalizeDouble(lot / 2.0, 8);
   ENUM_ORDER_TYPE_TIME tt    = ORDER_TIME_GTC;
   datetime             exp_t = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0) {
      tt = ORDER_TIME_SPECIFIED; exp_t = (datetime)(H2ExpireMsc(now_msc) / 1000) + 60;   // EA ลบเองตรงเวลา, โบรกเป็นตัวสำรอง
   }
   int placed = 0;
   for(int k = 0; k < 2; k++) {
      int    dir = (k == 0) ? 1 : -1;
      double px  = ND((dir == 1) ? ask + d : bid - d);
      double sl  = ND(px - dir * R);
      double tp1 = ND(px + dir * R * InpTP1_R);
      double tp2 = (InpTP2_R > 0.0) ? ND(px + dir * R * InpTP2_R) : 0.0;
      for(int leg = 0; leg < 2; leg++) {
         string cmt = InpOrderComment + " H2 " + (leg == 0 ? "A" : "B");
         double tp  = (leg == 0) ? tp1 : tp2;
         bool   ok  = (dir == 1) ? trade.BuyStop(half, px, _Symbol, sl, tp, tt, exp_t, cmt) : trade.SellStop(half, px, _Symbol, sl, tp, tt, exp_t, cmt);
         if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED)) placed++;
         else PrintFormat("❌ H2 วาง %s %s ไม่สำเร็จ: %u %s", (dir == 1 ? "BUY STOP" : "SELL STOP"), (leg == 0 ? "A" : "B"), trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
   if(placed == 0) return 0;
   g_last_status = StringFormat("✅ H2 วาง Stop %.2f+%.2f ฝั่งละ ±%.0f จุด | SL %.0f | อายุ %d นาที (%d/4 ออเดอร์)", half, half, InpH2_Dist_Pts, InpH2_SL_Pts, InpH2_Expire_Min, placed);
   Print(g_last_status);
   return 1;
}

void CloseOurPositions(string why) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      if(trade.PositionClose(t)) PrintFormat("🛑 ปิดไม้ #%I64u (%s)", t, why);
      else PrintFormat("❌ ปิดไม้ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", t, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

void CloseAllPositions() {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(t != 0 && IsOurOrder() && !trade.OrderDelete(t))
         PrintFormat("❌ ลบออเดอร์รอ #%I64u ไม่สำเร็จ: %u %s", t, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   CloseOurPositions("ก่อนตลาดปิดสัปดาห์");
}

//====================================================================
// 💼 EA จริง: บริบทแท่ง + สัญญาณ
//====================================================================
// แท่งปัจจุบันระบบไหนเปิด / วางไปแล้วบ้าง (คืนค่าเมื่อเริ่ม EA / ขึ้นแท่งใหม่)
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
      if(t != 0 && IsOurOrder() && (datetime)OrderGetInteger(ORDER_TIME_SETUP) >= bar) g_c.done[2] = true;
   }
   g_day_dirty = true;   // HistorySelect ถูกเปลี่ยนช่วง → สร้างสถานะวันใหม่
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

// ผลการส่งของระบบ s: สำเร็จ / ข้าม → ปิดระบบนี้ทั้งแท่ง, ส่งไม่สำเร็จ → ลองใหม่ 1 วิ
void LiveMark(int s, int res, datetime now) {
   if(res != 0) g_c.done[s] = true; else g_next_try[s] = now + 1;
}

// สัญญาณของ EA จริง (ทุก Tick + Timer) — ถือได้ทีละ 1 ชุด (รวมออเดอร์รอ)
void LiveSignals(int ts, double bid, double ask, long msc, bool tick) {
   if(!g_c.ready || !TradeAllowed()) return;
   if(OurPositionsTotal() > 0 || OurPendingTotal() > 0) return;
   datetime now = ServerNow();
   double   budget;
   string   why = EntryBlockReason(ts, bid, ask);
   string   gate = DayGate(g_day, AccountInfoDouble(ACCOUNT_BALANCE), budget);
   if(why == "") why = gate;
   // H1 / H3: ครบเวลาแล้วติดตัวกรอง → ทิ้งสัญญาณของแท่งนี้
   if(g_en[1] && !g_c.done[1] && now >= g_next_try[1]) {
      int d = H1Ready(g_c, msc);
      if(d != 0) {
         if(why != "") { g_c.done[1] = true; g_last_status = "H1 ครบเวลาแต่ติด: " + why; }
         else { LiveMark(1, OpenSet(1, d, bid, ask, H1SL(g_c, d), budget), now); return; }
      }
   }
   if(g_en[3] && !g_c.done[3] && now >= g_next_try[3]) {
      int d = H3Ready(g_c, msc);
      if(d != 0) {
         if(why != "") { g_c.done[3] = true; g_last_status = "H3 ครบเวลาแต่ติด: " + why; }
         else { LiveMark(3, OpenSet(3, d, bid, ask, H3SL(g_c, d), budget), now); return; }
      }
   }
   if(why != "" || !tick) return;   // H4 / H2: เงื่อนไขต่อเนื่อง → รอ tick ถัดไป
   if(g_en[4] && !g_c.done[4] && now >= g_next_try[4]) {
      int d = H4Dir(g_c, msc);
      if(d != 0) { LiveMark(4, OpenSet(4, d, bid, ask, H4SL(g_w, msc, d, (d == 1) ? bid : ask), budget), now); return; }
   }
   if(g_en[2] && !g_c.done[2] && now >= g_next_try[2] && H2Sig(g_c) != 0)
      LiveMark(2, PlaceStraddle(bid, ask, budget, msc), now);
}

//====================================================================
// 💼 EA จริง: จัดการออเดอร์รอ + ชุดไม้ (ทุก Tick + Timer 200 ms)
//====================================================================
// สร้างสถานะชุดจากไม้ที่ถืออยู่ (ชุดใหม่ / รีสตาร์ท) — R คำนวณย้อนจาก TP ของไม้
void LiveSetSync(long now_msc) {
   ulong tk[2];
   tk[0] = 0; tk[1] = 0;
   int    n = 0, sys = 0, dir = 0;
   double lots = 0.0, wsum = 0.0, rA = 0.0, rB = 0.0, slB = 0.0;
   long   t0 = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      string c   = PositionGetString(POSITION_COMMENT);
      int    leg = LegFromComment(c);
      if(leg < 0) leg = (tk[0] == 0) ? 0 : 1;
      tk[leg] = t; n++;
      sys = SysFromComment(c);
      dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double e = PositionGetDouble(POSITION_PRICE_OPEN), v = PositionGetDouble(POSITION_VOLUME), tp = PositionGetDouble(POSITION_TP);
      lots += v; wsum += e * v;
      long om = PositionGetInteger(POSITION_TIME_MSC);
      if(t0 == 0 || om < t0) t0 = om;
      if(tp > 0.0) { if(leg == 0 && InpTP1_R > 0.0) rA = MathAbs(tp - e) / InpTP1_R; if(leg == 1 && InpTP2_R > 0.0) rB = MathAbs(tp - e) / InpTP2_R; }
      if(leg == 1) slB = PositionGetDouble(POSITION_SL);
   }
   if(n == 0) { g_set.on = false; return; }
   bool same = g_set.on && ((tk[0] == 0 || tk[0] == g_set.tk[0]) && (tk[1] == 0 || tk[1] == g_set.tk[1]));
   g_set.tk[0] = tk[0]; g_set.tk[1] = tk[1];
   if(same) return;
   g_set.on          = true;
   g_set.ps.sys      = sys;
   g_set.ps.dir      = dir;
   g_set.ps.entry    = (lots > 0.0) ? wsum / lots : 0.0;
   g_set.ps.R        = (rA > 0.0) ? rA : ((rB > 0.0) ? rB : PtsToPrice(InpMinSL_Pts));
   g_set.ps.open_msc = (t0 > 0) ? t0 : now_msc;
   g_set.ps.mfe      = 0.0;
   g_set.ps.mfe_msc  = now_msc;
   g_set.ps.stage    = (slB > 0.0 && (dir == 1 ? slB > g_set.ps.entry : slB < g_set.ps.entry)) ? 1 : 0;
   g_set.ps.fc_done  = (now_msc - g_set.ps.open_msc > (long)InpFastCut_Sec * 1000);   // รีสตาร์ทหลังพ้นช่วงตัดเร็ว → ไม่ตัด
   g_set.ps.lock     = false;
   g_set.last_mod    = 0;
   g_set.next_try    = 0;
}

void ManageLive(datetime now, int ts, long now_msc) {
   // 1) ไม้ที่ถือ → ทิศของชุด
   LiveSetSync(now_msc);
   int pos_dir = g_set.on ? g_set.ps.dir : 0;
   // 2) H2 ออเดอร์รอ: หมดอายุ / อีกฝั่งถูกเกี่ยวแล้ว (OCO) / ช่วงห้ามเข้าก่อนปิดสัปดาห์ → ลบ
   if(now >= g_del_retry) {
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong t = OrderGetTicket(i);
         if(t == 0 || !IsOurOrder()) continue;
         int  odir    = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) ? 1 : -1;
         bool expired = (now_msc >= H2ExpireMsc(OrderGetInteger(ORDER_TIME_SETUP_MSC)));
         bool oco     = (pos_dir != 0 && odir != pos_dir);
         if(!expired && !oco && ts != TS_WAIT_CLOSE && ts != TS_CLOSING) continue;
         if(trade.OrderDelete(t)) PrintFormat("🗑️ ลบ H2 #%I64u (%s)", t, oco ? "อีกฝั่งถูกเกี่ยวแล้ว" : (expired ? "หมดอายุ" : "ช่วงห้ามเข้า"));
         else { g_del_retry = now + 1; PrintFormat("❌ ลบ H2 #%I64u ไม่สำเร็จ: %u %s", t, trade.ResultRetcode(), trade.ResultRetcodeDescription()); }
      }
   }
   if(!g_set.on || now_msc < g_set.next_try) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;
   int dir = g_set.ps.dir;
   SetMfe(g_set.ps, bid, ask, now_msc);
   // 3) ตัดเร็ว / ครบเวลาถือ
   long ev;
   int  rx = SetTimeExit(g_set.ps, now_msc, ev);
   if(rx != 0) { CloseOurPositions(rx == RX_FAST ? "ตัดเร็ว: กำไรสูงสุดไม่ถึงเกณฑ์" : "ครบเวลาถือ"); g_set.next_try = now_msc + 300; return; }
   // 4) กำไรลอย → ล็อกเป้า / พื้นฉุกเฉิน
   double floating = 0.0, lots = 0.0, wsum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      lots     += PositionGetDouble(POSITION_VOLUME);
      wsum     += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
   }
   double lf = LockFloor(g_day);
   if(!g_set.ps.lock && g_day.closed + floating >= lf + InpTargetLockBuf_USD) {
      g_set.ps.lock = true;
      g_last_status = StringFormat("🔒 ล็อกเป้า: ปิดแล้ว $%.2f + ลอย $%.2f → ขยับ SL ให้ชนแล้วยังได้ ≥ $%.2f", g_day.closed, floating, lf);
      Print(g_last_status);
   }
   double hf = DayFloor(g_day);
   if(g_set.ps.lock) hf = MathMax(hf, lf);
   if(g_day.closed + floating <= hf) {
      CloseOurPositions(StringFormat("กำไรรวม $%.2f แตะพื้น $%.2f", g_day.closed + floating, hf));
      g_set.next_try = now_msc + 300;
      return;
   }
   double lock_sl = (g_set.ps.lock && lots > 0.0) ? LockSL(dir, g_day.closed, lf, lots, wsum / lots) : 0.0;
   // 5) SL: B ทุน / ไล่จี้, ทุกไม้ล็อกเป้า
   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   int    stB;
   double bsl = SetBSL(g_set.ps, bid, ask, stB);
   for(int leg = 0; leg < 2; leg++) {
      ulong t = g_set.tk[leg];
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      double want = 0.0;
      bool   trail = false;
      if(leg == 1 && bsl != 0.0 && SLBetter(dir, bsl, sl)) { want = bsl; trail = (stB >= 2); }
      if(lock_sl != 0.0 && SLBetter(dir, lock_sl, sl) && (want == 0.0 || SLBetter(dir, lock_sl, want))) { want = lock_sl; trail = false; }
      if(want == 0.0) continue;
      want = ND(want);
      if(trail && (now_msc - g_set.last_mod < 1000 || !SLBetter(dir, want, sl + dir * PtsToPrice(InpTrailStep_Pts) - dir * _Point))) continue;
      if(dir == 1 ? (bid - want < stops) : (want - ask < stops)) continue;          // Stops Level → รอ tick ถัดไป
      if(sl > 0.0 && (dir == 1 ? (bid - sl <= freeze) : (sl - ask <= freeze))) continue; // Freeze Level
      if(trade.PositionModify(t, want, tp)) {
         if(leg == 1 && stB != g_set.ps.stage)
            PrintFormat("🛡️ #%I64u %s ไม้ B %s: SL → %s", t, SysTag(g_set.ps.sys), (stB >= 2 ? "ไล่จี้" : "ทุน"), DoubleToString(want, _Digits));
         g_set.last_mod = now_msc;
      } else { g_set.next_try = now_msc + 1000; PrintFormat("⚠️ ขยับ SL #%I64u ไม่สำเร็จ: %u %s", t, trade.ResultRetcode(), trade.ResultRetcodeDescription()); }
   }
   if(bsl != 0.0) g_set.ps.stage = MathMax(g_set.ps.stage, stB);
}

//====================================================================
// 🧪 TICK REPLAY — เล่นซ้ำ tick จริงด้วยฟังก์ชันตัดสินใจชุดเดียวกับ EA จริง
//====================================================================
struct RSet {
   int      sys;
   long     msc_in;
   double   sl0, lot, tp[2];
   double   zr_in, zs_in;
   SetSt    ps;
   double   sl[2];
   int      src[2];          // ที่มาของ SL: 0 แรก / 1 ทุน / 2 ไล่จี้ / 3 ล็อกเป้า
   bool     open[2];
   long     out_msc[2];
   double   out_px[2];
   int      reason[2];
   double   usd[2];
   long     last_mod;
   double   day_after, bal_after;
   bool     done;
   bool     drawn_final;
};

struct RPend {               // H2 Stop จำลอง (1 รายการ = 1 ฝั่ง, lot รวม A + B)
   int      dir;
   double   price, lot;
   long     msc_set, exp_msc, msc_end;
   int      state;           // 0 รอ / 1 ถูกเกี่ยว / 2 หมดอายุ / ยกเลิก
   bool     drawn_final;
};

struct RDay {
   datetime day;
   double   bal0, pnl, peak, low;
   int      sets, wins, consec;
   double   px;              // ราคาแรกของวัน (วางป้าย)
   bool     drawn;
};

RSet     g_rs[];
RPend    g_rpd[];
RDay     g_rdays[];
int      g_rcur         = -1;  // ชุดที่ถืออยู่ (index ใน g_rs)
DaySt    g_rday;
double   g_rbal         = 0.0;
double   g_rday_px      = 0.0;
Ctx      g_rc;
Win60    g_rw;
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
int      g_rp_csv_days  = -1;
string   g_rp_status    = "ยังไม่เริ่ม";

void ReplayReset() {
   ArrayResize(g_rs, 0); ArrayResize(g_rpd, 0); ArrayResize(g_rdays, 0); ArrayResize(g_rr, 0);
   g_rcur = -1;
   DayReset(g_rday, 0);
   g_rbal = InpReplayBalance; g_rday_px = 0.0;
   CtxReset(g_rc);
   WinReset(g_rw);
   g_rp_b = -1; g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_msc = 0;
   g_rp_have = false; g_rp_init = false; g_rp_caught = false; g_rp_cursor = 0; g_rp_retry = 0;
   g_rp_fail_cur = -1; g_rp_fail_ms = 0; g_rp_skip_n = 0;
   ArrayResize(g_rp_buf, 0); g_rp_buf_i = 0; g_rp_buf_n = 0; g_rp_buf_to = 0;
   g_rp_ticks = 0; g_rp_csv_rows = -1; g_rp_csv_days = -1; g_rp_status = "ยังไม่เริ่ม";
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

bool ReplayBusy() {
   if(g_rcur >= 0) return true;
   for(int k = 0; k < ArraySize(g_rpd); k++) if(g_rpd[k].state == 0) return true;
   return false;
}

// เปิดชุดจำลอง (entry = ราคาที่ได้, R = ระยะ SL ราคา, lot รวม)
void ReplayOpenSet(int sys, int dir, long msc, double entry, double R, double lot) {
   int i = ArraySize(g_rs);
   ArrayResize(g_rs, i + 1, 256);
   g_rs[i].sys = sys; g_rs[i].msc_in = msc; g_rs[i].lot = lot;
   g_rs[i].sl0 = entry - dir * R;
   g_rs[i].tp[0] = entry + dir * R * InpTP1_R;
   g_rs[i].tp[1] = (InpTP2_R > 0.0) ? entry + dir * R * InpTP2_R : 0.0;
   g_rs[i].zr_in = g_rc.zr; g_rs[i].zs_in = g_rc.zs;
   g_rs[i].ps.sys = sys; g_rs[i].ps.dir = dir; g_rs[i].ps.entry = entry; g_rs[i].ps.R = R; g_rs[i].ps.open_msc = msc;
   g_rs[i].ps.mfe = 0.0; g_rs[i].ps.mfe_msc = msc; g_rs[i].ps.stage = 0; g_rs[i].ps.fc_done = false; g_rs[i].ps.lock = false;
   for(int k = 0; k < 2; k++) {
      g_rs[i].sl[k] = g_rs[i].sl0; g_rs[i].src[k] = 0; g_rs[i].open[k] = true;
      g_rs[i].out_msc[k] = 0; g_rs[i].out_px[k] = 0.0; g_rs[i].reason[k] = RX_OPEN; g_rs[i].usd[k] = 0.0;
   }
   g_rs[i].last_mod = 0; g_rs[i].day_after = 0.0; g_rs[i].bal_after = 0.0; g_rs[i].done = false; g_rs[i].drawn_final = false;
   g_rcur = i;
   g_rc.done[sys] = true;
}

// เปิดชุด Market จำลองด้วยกฎรายวัน (เปิดได้หรือข้าม → ระบบนี้จบแท่งเหมือนไม้จริง)
void ReplayTryMarket(int sys, int dir, long msc, double bid, double ask, double sl_raw) {
   double budget;
   string gate = DayGate(g_rday, g_rbal, budget);
   g_rc.done[sys] = true;
   if(gate != "") return;
   double entry = (dir == 1) ? ask : bid;
   double R     = ClampR(dir, entry, sl_raw);
   double lot   = LotFor(budget, R + (ask - bid));
   if(lot > 0.0) ReplayOpenSet(sys, dir, msc, entry, R, lot);
}

// ปิดไม้ k ของชุดที่ถือ
void ReplayCloseLeg(int k, long msc, double px, int reason) {
   int i = g_rcur;
   if(i < 0 || !g_rs[i].open[k]) return;
   double usd = g_rs[i].ps.dir * (px - g_rs[i].ps.entry) * (g_rs[i].lot / 2.0) * g_vpp;
   g_rs[i].open[k] = false; g_rs[i].out_msc[k] = msc; g_rs[i].out_px[k] = px; g_rs[i].reason[k] = reason; g_rs[i].usd[k] = usd;
   g_rbal += usd;
   DayAddLeg(g_rday, usd);
   if(!g_rs[i].open[0] && !g_rs[i].open[1]) {
      DaySetClosed(g_rday, g_rs[i].usd[0] + g_rs[i].usd[1]);
      g_rs[i].day_after = g_rday.closed; g_rs[i].bal_after = g_rbal; g_rs[i].done = true;
      g_rcur = -1;
   }
}

void ReplayCloseAll(long msc, double bid, double ask, int reason) {
   int i = g_rcur;
   if(i < 0) return;
   double px = (g_rs[i].ps.dir == 1) ? bid : ask;
   for(int k = 0; k < 2; k++) if(g_rcur >= 0 && g_rs[i].open[k]) ReplayCloseLeg(k, msc, px, reason);
}

// จบวัน → เก็บสรุปวัน
void ReplayDayFinish() {
   if(g_rday.day <= 0) return;
   int n = ArraySize(g_rdays);
   ArrayResize(g_rdays, n + 1, 64);
   g_rdays[n].day = g_rday.day; g_rdays[n].pnl = g_rday.closed; g_rdays[n].peak = g_rday.peak; g_rdays[n].low = g_rday.low;
   g_rdays[n].sets = g_rday.sets; g_rdays[n].wins = g_rday.wins; g_rdays[n].consec = g_rday.consec;
   g_rdays[n].bal0 = g_rbal - g_rday.closed; g_rdays[n].px = g_rday_px; g_rdays[n].drawn = false;
}

// เหตุการณ์ตามเวลาด้วยราคาของ tick ก่อนหน้า: วันใหม่ / H2 หมดอายุ / ปิดสัปดาห์ / ตัดเร็ว / ครบเวลา / H1 H3 ครบเวลาไม่มียอดใหม่
void ReplayTimeEvents(long msc) {
   if(!g_rp_have) return;
   datetime t = (datetime)(msc / 1000);
   if(DayStartOf(t) != g_rday.day) { ReplayDayFinish(); DayReset(g_rday, DayStartOf(t)); g_rday_px = 0.0; }
   int ts = GetTimeStateAt(t);
   for(int k = 0; k < ArraySize(g_rpd); k++) {
      if(g_rpd[k].state != 0) continue;
      if(msc >= g_rpd[k].exp_msc)                    { g_rpd[k].state = 2; g_rpd[k].msc_end = g_rpd[k].exp_msc; }
      else if(ts == TS_WAIT_CLOSE || ts == TS_CLOSING) { g_rpd[k].state = 2; g_rpd[k].msc_end = msc; }
   }
   if(g_rcur >= 0) {
      int      i  = g_rcur;
      datetime fc = ForceCloseTimeAt((datetime)(g_rs[i].msc_in / 1000));
      long     ev = 0;
      if(fc > 0 && msc >= (long)fc * 1000) ReplayCloseAll((long)fc * 1000, g_rp_bid, g_rp_ask, RX_WEEK);
      else {
         int rx = SetTimeExit(g_rs[i].ps, msc, ev);
         if(rx != 0) ReplayCloseAll(ev, g_rp_bid, g_rp_ask, rx);
      }
   }
   if(ReplayBusy() || g_rc.bar <= 0) return;
   long bar_end = ((long)g_rc.bar + PeriodSeconds(InpZ_Timeframe)) * 1000;   // ยิงได้ภายในแท่งของสัญญาณเท่านั้น
   long lim     = MathMin(msc, bar_end - 1);
   for(int q = 0; q < 2; q++) {
      int sys = (q == 0) ? 1 : 3;
      if(!g_en[sys] || g_rc.done[sys]) continue;
      int d = (sys == 1) ? H1Ready(g_rc, lim) : H3Ready(g_rc, lim);
      if(d == 0) continue;
      int  s    = (d == -1) ? 0 : 1;
      long fire = MathMax((sys == 1) ? H1Deadline(g_rc, s) : H3Deadline(g_rc, s), g_rp_msc);
      if(EntryBlockReason(GetTimeStateAt((datetime)(fire / 1000)), g_rp_bid, g_rp_ask) != "") { g_rc.done[sys] = true; continue; }
      ReplayTryMarket(sys, d, fire, g_rp_bid, g_rp_ask, (sys == 1) ? H1SL(g_rc, d) : H3SL(g_rc, d));
      if(ReplayBusy()) return;
   }
}

// ชุดที่ถือ: SL / TP → กำไรสูงสุด → B ทุน / ไล่จี้ → ล็อกเป้า → พื้นฉุกเฉิน (ฟังก์ชันเดียวกับ EA จริง)
void ReplayManage(long msc, double bid, double ask) {
   int i = g_rcur;
   if(i < 0) return;
   int    d  = g_rs[i].ps.dir;
   double px = (d == 1) ? bid : ask;
   for(int k = 0; k < 2 && g_rcur >= 0; k++) {
      if(!g_rs[i].open[k]) continue;
      if(d == 1 ? (bid <= g_rs[i].sl[k]) : (ask >= g_rs[i].sl[k])) {
         int src = g_rs[i].src[k];
         ReplayCloseLeg(k, msc, px, (src == 3) ? RX_LOCK : ((src == 2) ? RX_TRAIL : ((src == 1) ? RX_BE : RX_SL)));
      } else if(g_rs[i].tp[k] > 0.0 && (d == 1 ? (bid >= g_rs[i].tp[k]) : (ask <= g_rs[i].tp[k])))
         ReplayCloseLeg(k, msc, g_rs[i].tp[k], (k == 0) ? RX_TP1 : RX_TP2);
   }
   if(g_rcur < 0) return;
   SetMfe(g_rs[i].ps, bid, ask, msc);
   if(g_rs[i].open[1]) {
      int    stB;
      double bsl = SetBSL(g_rs[i].ps, bid, ask, stB);
      if(bsl != 0.0 && SLBetter(d, bsl, g_rs[i].sl[1]) &&
         (stB < 2 || (msc - g_rs[i].last_mod >= 1000 && SLBetter(d, bsl, g_rs[i].sl[1] + d * PtsToPrice(InpTrailStep_Pts) - d * _Point)))) {
         g_rs[i].sl[1] = bsl; g_rs[i].src[1] = (stB >= 2) ? 2 : 1; g_rs[i].last_mod = msc;
      }
      if(bsl != 0.0) g_rs[i].ps.stage = MathMax(g_rs[i].ps.stage, stB);
   }
   double lots = 0.0, floating = 0.0;
   for(int k = 0; k < 2; k++) if(g_rs[i].open[k]) { lots += g_rs[i].lot / 2.0; floating += d * (px - g_rs[i].ps.entry) * (g_rs[i].lot / 2.0) * g_vpp; }
   double lf = LockFloor(g_rday);
   if(!g_rs[i].ps.lock && g_rday.closed + floating >= lf + InpTargetLockBuf_USD) g_rs[i].ps.lock = true;
   double hf = DayFloor(g_rday);
   if(g_rs[i].ps.lock) hf = MathMax(hf, lf);
   if(g_rday.closed + floating <= hf) { ReplayCloseAll(msc, bid, ask, RX_FLOOR); return; }
   if(g_rs[i].ps.lock) {
      double s = LockSL(d, g_rday.closed, lf, lots, g_rs[i].ps.entry);
      for(int k = 0; k < 2; k++) if(g_rs[i].open[k] && s != 0.0 && SLBetter(d, s, g_rs[i].sl[k]) && (d == 1 ? s < bid : s > ask)) { g_rs[i].sl[k] = s; g_rs[i].src[k] = 3; }
   }
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);
   ReplayTimeEvents(msc);                 // A) เหตุการณ์ตามเวลา (ราคาของ tick ก่อนหน้า)
   if(g_rday.day != DayStartOf(t)) { ReplayDayFinish(); DayReset(g_rday, DayStartOf(t)); g_rday_px = 0.0; }
   if(g_rday_px <= 0.0) g_rday_px = bid;
   WinAdd(g_rw, msc, bid);
   if(!ReplayBarFor(t)) { g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc; g_rp_have = true; return; }   // B) แท่งของ tick นี้
   CtxTick(g_rc, bid, msc);               // C) High / Low / Z / H1 / H3 / K2
   ReplayManage(msc, bid, ask);           // D) ชุดที่ถือ
   for(int k = 0; k < ArraySize(g_rpd); k++) {   // E) H2 Stop ถูกเกี่ยว (ได้ราคาของ tick, อีกฝั่งยกเลิก)
      if(g_rpd[k].state != 0 || g_rcur >= 0) continue;
      bool hit = (g_rpd[k].dir == 1) ? (ask >= g_rpd[k].price) : (bid <= g_rpd[k].price);
      if(!hit) continue;
      g_rpd[k].state = 1; g_rpd[k].msc_end = msc;
      double fill = (g_rpd[k].dir == 1) ? ask : bid;
      double R    = PtsToPrice(InpH2_SL_Pts) + g_rpd[k].dir * (fill - g_rpd[k].price);   // SL / TP วางจากราคา Stop
      ReplayOpenSet(2, g_rpd[k].dir, msc, fill, MathMax(R, _Point), g_rpd[k].lot);
      g_rs[g_rcur].sl0 = g_rpd[k].price - g_rpd[k].dir * PtsToPrice(InpH2_SL_Pts);
      g_rs[g_rcur].sl[0] = g_rs[g_rcur].sl0; g_rs[g_rcur].sl[1] = g_rs[g_rcur].sl0;
      g_rs[g_rcur].tp[0] = g_rpd[k].price + g_rpd[k].dir * PtsToPrice(InpH2_SL_Pts) * InpTP1_R;
      g_rs[g_rcur].tp[1] = (InpTP2_R > 0.0) ? g_rpd[k].price + g_rpd[k].dir * PtsToPrice(InpH2_SL_Pts) * InpTP2_R : 0.0;
      g_rs[g_rcur].ps.R  = PtsToPrice(InpH2_SL_Pts);
      for(int q = 0; q < ArraySize(g_rpd); q++) if(q != k && g_rpd[q].state == 0) { g_rpd[q].state = 2; g_rpd[q].msc_end = msc; }
   }
   if(!ReplayBusy() && EntryBlockReason(GetTimeStateAt(t), bid, ask) == "") {
      double budget;
      bool   gate_ok = (DayGate(g_rday, g_rbal, budget) == "");
      if(gate_ok && g_en[4] && !g_rc.done[4]) {                      // F) H4 ตามแรงกระชาก
         int d = H4Dir(g_rc, msc);
         if(d != 0) ReplayTryMarket(4, d, msc, bid, ask, H4SL(g_rw, msc, d, (d == 1) ? bid : ask));
      }
      if(gate_ok && !ReplayBusy() && g_en[2] && !g_rc.done[2] && H2Sig(g_rc) != 0) {   // G) H2 วาง Stop
         g_rc.done[2] = true;
         double lot = LotFor(budget, PtsToPrice(InpH2_SL_Pts) + (ask - bid));
         if(lot > 0.0) {
            for(int k = 0; k < 2; k++) {
               int n = ArraySize(g_rpd);
               ArrayResize(g_rpd, n + 1, 64);
               g_rpd[n].dir = (k == 0) ? 1 : -1;
               g_rpd[n].price = (k == 0) ? ask + PtsToPrice(InpH2_Dist_Pts) : bid - PtsToPrice(InpH2_Dist_Pts);
               g_rpd[n].lot = lot; g_rpd[n].msc_set = msc; g_rpd[n].exp_msc = H2ExpireMsc(msc); g_rpd[n].msc_end = 0;
               g_rpd[n].state = 0; g_rpd[n].drawn_final = false;
            }
         }
      }
   }
   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc; g_rp_have = true; g_rp_ticks++;
}

string ReasonName(int r) {
   switch(r) {
      case RX_SL:    return "SL";
      case RX_TP1:   return "TP1";
      case RX_TP2:   return "TP2";
      case RX_BE:    return "ทุน";
      case RX_TRAIL: return "ไล่จี้";
      case RX_LOCK:  return "ล็อกเป้า";
      case RX_FAST:  return "ตัดเร็ว";
      case RX_TIME:  return "ครบเวลา";
      case RX_FLOOR: return "แตะพื้น";
      case RX_WEEK:  return "ปิดสัปดาห์";
   }
   return "ถืออยู่";
}

string ReasonCode(int r) {
   switch(r) {
      case RX_SL:    return "SL";
      case RX_TP1:   return "TP1";
      case RX_TP2:   return "TP2";
      case RX_BE:    return "BE";
      case RX_TRAIL: return "TRAIL";
      case RX_LOCK:  return "LOCK";
      case RX_FAST:  return "FASTCUT";
      case RX_TIME:  return "TIME";
      case RX_FLOOR: return "FLOOR";
      case RX_WEEK:  return "WEEKCLOSE";
   }
   return "OPEN";
}

double RSetUsd(int i) { return g_rs[i].usd[0] + g_rs[i].usd[1]; }

void DrawReplaySet(int i) {
   datetime t_in = (datetime)(g_rs[i].msc_in / 1000);
   bool     buy  = (g_rs[i].ps.dir == 1);
   color    clr  = SysColor(g_rs[i].sys);
   string   id   = IntegerToString(g_rs[i].msc_in) + "_" + IntegerToString(i);
   string   na = OBJ_PREFIX + "RP_A_" + id, nt = OBJ_PREFIX + "RP_T_" + id;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, buy ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, t_in, g_rs[i].ps.entry);
      ObjectSetInteger(0, na, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }
   string legs = "";
   for(int k = 0; k < 2; k++) {
      string nl = OBJ_PREFIX + "RP_L" + IntegerToString(k) + "_" + id;
      if(g_rs[i].open[k]) { legs += StringFormat(" | %s ถือ", (k == 0 ? "A" : "B")); continue; }
      legs += StringFormat(" | %s %s $%+.2f", (k == 0 ? "A" : "B"), ReasonName(g_rs[i].reason[k]), g_rs[i].usd[k]);
      if(ObjectFind(0, nl) < 0) {
         ObjectCreate(0, nl, OBJ_TREND, 0, t_in, g_rs[i].ps.entry, (datetime)(g_rs[i].out_msc[k] / 1000), g_rs[i].out_px[k]);
         ObjectSetInteger(0, nl, OBJPROP_STYLE, (k == 0) ? STYLE_DOT : STYLE_DASH);
         ObjectSetInteger(0, nl, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nl, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, nl, OBJPROP_COLOR, (g_rs[i].usd[k] > 0.0) ? InpClrWin : InpClrLoss);
   }
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_in, g_rs[i].ps.entry);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   double tot = RSetUsd(i);
   string mfe = StringFormat(" | สูงสุด %+.0f @%s", PriceToPts(g_rs[i].ps.mfe), ShortSec((g_rs[i].ps.mfe_msc - g_rs[i].msc_in) / 1000));
   ObjectSetInteger(0, nt, OBJPROP_COLOR, !g_rs[i].done ? clr : ((tot > 0.0) ? InpClrWin : InpClrLoss));
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("%s %s %.2f%s%s%s   ", SysTag(g_rs[i].sys), (buy ? "B" : "S"), g_rs[i].lot, legs,
                                                     (g_rs[i].done ? StringFormat(" | รวม $%+.2f", tot) : ""), mfe));
   string tip = StringFormat("จำลอง %s %s %.2f (A %.2f + B %.2f) @ %s (%s) | SL %s (%.0f จุด) | TP1 %s | TP2 %s | Z ตอนเข้า R %+.2f / S %+.2f",
                             SysTag(g_rs[i].sys), (buy ? "BUY" : "SELL"), g_rs[i].lot, g_rs[i].lot / 2.0, g_rs[i].lot / 2.0,
                             DoubleToString(g_rs[i].ps.entry, _Digits), TimeToString(t_in, TIME_DATE|TIME_SECONDS),
                             DoubleToString(g_rs[i].sl0, _Digits), PriceToPts(g_rs[i].ps.R), DoubleToString(g_rs[i].tp[0], _Digits),
                             DoubleToString(g_rs[i].tp[1], _Digits), g_rs[i].zr_in, g_rs[i].zs_in);
   if(g_rs[i].done)
      tip += StringFormat("\nรวม $%+.2f | กำไรวันหลังชุดนี้ $%+.2f | ทุน $%.2f | กำไรสูงสุด %+.0f จุด", tot, g_rs[i].day_after, g_rs[i].bal_after, PriceToPts(g_rs[i].ps.mfe));
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tip);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tip);
   g_rs[i].drawn_final = (g_rs[i].done && iBarShift(_Symbol, InpZ_Timeframe, t_in, false) > 0);
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
   ObjectSetInteger(0, nm, OBJPROP_COLOR, (g_rpd[k].state == 2) ? clrDimGray : InpClrH2);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, StringFormat("H2 %s @ %s | %.2f lot | %s", (g_rpd[k].dir == 1 ? "BUY STOP" : "SELL STOP"),
                                                        DoubleToString(g_rpd[k].price, _Digits), g_rpd[k].lot,
                                                        (g_rpd[k].state == 0 ? "รอ" : (g_rpd[k].state == 1 ? "ถูกเกี่ยว" : "ไม่ถูกเกี่ยว / ยกเลิก"))));
   g_rpd[k].drawn_final = (g_rpd[k].state != 0);
}

// ป้ายสรุปวันที่จุดเริ่มวัน
void DrawReplayDay(int k) {
   string nm = OBJ_PREFIX + "RP_D_" + IntegerToString((long)g_rdays[k].day);
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_TEXT, 0, g_rdays[k].day, g_rdays[k].px);
      ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   bool hit = (g_rdays[k].peak >= InpDailyTarget_USD);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, hit ? InpClrWin : ((g_rdays[k].pnl < 0.0) ? InpClrLoss : clrSilver));
   ObjectSetString(0, nm, OBJPROP_TEXT, StringFormat("📅 %s $%+.2f (%d ชุด)%s", TimeToString(g_rdays[k].day, TIME_DATE), g_rdays[k].pnl, g_rdays[k].sets, hit ? " ✅ ถึงเป้า" : ""));
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, StringFormat("ทุนต้นวัน $%.2f | กำไรปิดแล้วสูงสุด $%+.2f / ต่ำสุด $%+.2f | ชนะ %d/%d ชุด",
                                                        g_rdays[k].bal0, g_rdays[k].peak, g_rdays[k].low, g_rdays[k].wins, g_rdays[k].sets));
   g_rdays[k].drawn = true;
}

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rs); i++)    if(!g_rs[i].drawn_final)  DrawReplaySet(i);
   for(int k = 0; k < ArraySize(g_rpd); k++)   if(!g_rpd[k].drawn_final) DrawReplayPending(k);
   for(int k = 0; k < ArraySize(g_rdays); k++) if(!g_rdays[k].drawn)     DrawReplayDay(k);
}

string ReplayCSVName()    { return "7LGD_Replay_" + _Symbol + ".csv"; }
string ReplayDayCSVName() { return "7LGD_Days_" + _Symbol + ".csv"; }

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n[5];
   int    w[5];
   double u[5];
   ArrayInitialize(n, 0); ArrayInitialize(w, 0); ArrayInitialize(u, 0.0);
   int    rc[RX_N];
   ArrayInitialize(rc, 0);
   double tot = 0.0, peak = 0.0, dd = 0.0;
   for(int i = 0; i < ArraySize(g_rs); i++) {
      if(!g_rs[i].done) continue;
      int    sy = g_rs[i].sys;
      double v  = RSetUsd(i);
      n[sy]++; n[0]++; u[sy] += v; u[0] += v;
      if(v > 0.0) { w[sy]++; w[0]++; }
      for(int k = 0; k < 2; k++) rc[g_rs[i].reason[k]]++;
      tot += v;
      if(tot > peak) peak = tot;
      if(tot - peak < dd) dd = tot - peak;
   }
   int    nd = ArraySize(g_rdays), hit = 0, lossd = 0;
   double dsum = 0.0;
   for(int k = 0; k < nd; k++) {
      dsum += g_rdays[k].pnl;
      if(g_rdays[k].peak >= InpDailyTarget_USD) hit++;
      if(g_rdays[k].pnl < 0.0) lossd++;
   }
   string s = StringFormat("🧪 Replay %d วัน (ทุน $%.0f → $%.2f): %s\n   %d ชุด | ชนะ %.0f%% | สุทธิ $%+.2f | DD $%.2f",
                           InpReplayDays, InpReplayBalance, g_rbal, g_rp_status, n[0], (n[0] > 0 ? 100.0 * w[0] / n[0] : 0.0), u[0], dd);
   s += StringFormat("\n   วัน: %d วัน | ถึงเป้า %d | ขาดทุน %d | เฉลี่ย $%+.2f/วัน", nd, hit, lossd, (nd > 0 ? dsum / nd : 0.0));
   s += StringFormat("\n   ออก: TP1 %d TP2 %d SL %d ทุน %d ไล่จี้ %d ล็อกเป้า %d ตัดเร็ว %d ครบเวลา %d แตะพื้น %d",
                     rc[RX_TP1], rc[RX_TP2], rc[RX_SL], rc[RX_BE], rc[RX_TRAIL], rc[RX_LOCK], rc[RX_FAST], rc[RX_TIME], rc[RX_FLOOR]);
   for(int k = 1; k <= 4; k++)
      s += StringFormat("%s%s %d ชุด ชนะ %.0f%% $%+.2f", (k == 1 ? "\n   " : " | "), SysTag(k), n[k], (n[k] > 0 ? 100.0 * w[k] / n[k] : 0.0), u[k]);
   if(g_rp_skip_n > 0) s += StringFormat(" | ⚠️ ข้ามช่วงที่ดึง tick ไม่ได้ %d ช่วง", g_rp_skip_n);
   if(InpReplayCSV && g_rp_csv_rows >= 0) s += StringFormat("\n   📄 CSV: MQL5\\Files\\%s (%d ชุด) + %s (%d วัน)", ReplayCSVName(), g_rp_csv_rows, ReplayDayCSVName(), MathMax(0, g_rp_csv_days));
   return s;
}

void ReplayWriteCSV(int done) {
   string fn = ReplayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "system,side,time_in,price_in,sl_init,r_pts,lot,z_reg_in,z_sma_in," +
                      "A_exit,A_time,A_price,A_usd,B_exit,B_time,B_price,B_usd,usd_total,profit_max_pts,profit_max_sec,hold_sec,day_closed_after,balance_after\r\n");
   for(int i = 0; i < ArraySize(g_rs); i++) {
      if(!g_rs[i].done) continue;
      string ln = StringFormat("%s,%s,%s,%s,%s,%.0f,%.2f,%.3f,%.3f,", SysTag(g_rs[i].sys), (g_rs[i].ps.dir == 1 ? "BUY" : "SELL"),
                               TimeToString((datetime)(g_rs[i].msc_in / 1000), TIME_DATE|TIME_SECONDS), DoubleToString(g_rs[i].ps.entry, _Digits),
                               DoubleToString(g_rs[i].sl0, _Digits), PriceToPts(g_rs[i].ps.R), g_rs[i].lot, g_rs[i].zr_in, g_rs[i].zs_in);
      long out = 0;
      for(int k = 0; k < 2; k++) {
         ln += StringFormat("%s,%s,%s,%.2f,", ReasonCode(g_rs[i].reason[k]), TimeToString((datetime)(g_rs[i].out_msc[k] / 1000), TIME_DATE|TIME_SECONDS),
                            DoubleToString(g_rs[i].out_px[k], _Digits), g_rs[i].usd[k]);
         out = MathMax(out, g_rs[i].out_msc[k]);
      }
      ln += StringFormat("%.2f,%.0f,%d,%d,%.2f,%.2f\r\n", RSetUsd(i), PriceToPts(g_rs[i].ps.mfe), (int)((g_rs[i].ps.mfe_msc - g_rs[i].msc_in) / 1000),
                         (int)((out - g_rs[i].msc_in) / 1000), g_rs[i].day_after, g_rs[i].bal_after);
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_rp_csv_rows < 0) PrintFormat("📄 บันทึกชุดจำลอง %d ชุด ลง MQL5\\Files\\%s (อัปเดตเมื่อมีชุดปิดเพิ่ม)", done, fn);
   g_rp_csv_rows = done;
}

void ReplayWriteDayCSV() {
   string fn = ReplayDayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "day,start_balance,pnl,sets,wins,peak_closed,low_closed,reached_target,hit_max_loss,consec_loss_end\r\n");
   for(int k = 0; k < ArraySize(g_rdays); k++)
      FileWriteString(h, StringFormat("%s,%.2f,%.2f,%d,%d,%.2f,%.2f,%d,%d,%d\r\n", TimeToString(g_rdays[k].day, TIME_DATE), g_rdays[k].bal0, g_rdays[k].pnl,
                                      g_rdays[k].sets, g_rdays[k].wins, g_rdays[k].peak, g_rdays[k].low,
                                      (g_rdays[k].peak >= InpDailyTarget_USD ? 1 : 0), (g_rdays[k].pnl <= -InpDailyMaxLoss_USD + 1.0 ? 1 : 0), g_rdays[k].consec));
   FileClose(h);
   g_rp_csv_days = ArraySize(g_rdays);
}

// เรียกทุก 1 วินาที (นอกช่วงร้อน): โหลด tick ทีละช่วง (ครั้งแรก 12 ชม.) แล้วเล่นตามงบเวลา จนถึงปัจจุบัน แล้วต่อแบบสด
void ReplayStep() {
   if(!g_draw || !InpShowReplay) return;
   if(!g_rp_init) {
      if(!ReplayLoadRates()) { g_rp_status = "⏳ รอประวัติแท่ง"; return; }
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
      for(int i = 0; i < ArraySize(g_rs); i++) if(g_rs[i].done) done++;
      if(done != g_rp_csv_rows) ReplayWriteCSV(done);
      if(ArraySize(g_rdays) != g_rp_csv_days) ReplayWriteDayCSV();
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

// โซนไส้ของ H3 บนแท่งปัจจุบัน (ไม่ถึงเกณฑ์ = ลบ)
void DrawLevels() {
   string zu = OBJ_PREFIX + "ZONE_U", zd = OBJ_PREFIX + "ZONE_D";
   if(!g_draw || !InpShowLevels || !g_c.ready) { ObjectsDeleteAll(0, OBJ_PREFIX + "ZONE_"); return; }
   long     per = PeriodSeconds(InpZ_Timeframe);
   datetime t0  = g_c.bar - (datetime)per, t1 = g_c.bar + (datetime)per;
   if(H3Armed(g_c, 0))
      SetRect(zu, t0, MathMax(g_c.p_open, g_c.p_close), t1, g_c.p_high, g_c.sb[0] ? InpClrZoneOn : InpClrZone,
              StringFormat("H3 โซนไส้บน (Z ที่ High %+.2f)%s", g_c.p_zhi, g_c.sb_cancel[0] ? " — ยกเลิก (ทะลุยอด)" : (g_c.sb[0] ? " — สแตนบาย" : "")));
   else ObjectDelete(0, zu);
   if(H3Armed(g_c, 1))
      SetRect(zd, t0, g_c.p_low, t1, MathMin(g_c.p_open, g_c.p_close), g_c.sb[1] ? InpClrZoneOn : InpClrZone,
              StringFormat("H3 โซนไส้ล่าง (Z ที่ Low %+.2f)%s", g_c.p_zlo, g_c.sb_cancel[1] ? " — ยกเลิก (ทะลุยอด)" : (g_c.sb[1] ? " — สแตนบาย" : "")));
   else ObjectDelete(0, zd);
}

string SysStatusText(long msc) {
   string s = "H1 ";
   if(g_c.done[1]) s += "เปิดแล้วแท่งนี้";
   else if(g_c.h1_arm[0] || g_c.h1_arm[1]) {
      int k = g_c.h1_arm[0] ? 0 : 1;
      s += StringFormat("%s ยิงในอีก %.1f วิ", (k == 0 ? "SELL" : "BUY"), MathMax(0.0, (H1Deadline(g_c, k) - msc) / 1000.0));
   } else s += "รอ Z > " + DoubleToString(InpH1_Z, 1);
   s += " | H2 " + (g_c.done[2] ? "วางแล้วแท่งนี้" : "รอ Z ทั้งคู่ > " + DoubleToString(InpH2_Z, 1));
   s += " | H3 ";
   string h3 = "";
   for(int k = 0; k < 2; k++) {
      if(!H3Armed(g_c, k)) continue;
      string side = (k == 0) ? "SELL" : "BUY";
      if(g_c.sb_cancel[k])  h3 += side + " ยกเลิก ";
      else if(g_c.sb[k])    h3 += StringFormat("%s สแตนบาย %.1f วิ ", side, MathMax(0.0, (H3Deadline(g_c, k) - msc) / 1000.0));
      else                  h3 += side + " รอเข้าโซน ";
   }
   s += g_c.done[3] ? "เปิดแล้วแท่งนี้" : ((h3 == "") ? "แท่งก่อนไม่ถึงเกณฑ์" : h3);
   s += StringFormat(" | H4 K2 ↑%d ↓%d (ต้อง %d)%s", K2Count(g_c, 0, msc), K2Count(g_c, 1, msc), InpH4_K2, g_c.done[4] ? " เปิดแล้วแท่งนี้" : "");
   return s;
}

string PositionLines(double bid, double ask) {
   string out = "";
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !IsOurOrder()) continue;
      out += StringFormat("\n  ⏳ #%I64u %s %s %.2f @ %s | SL %s | TP %s", t, OrderGetString(ORDER_COMMENT),
                          (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP ? "BUY STOP" : "SELL STOP"), OrderGetDouble(ORDER_VOLUME_CURRENT),
                          DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), _Digits), DoubleToString(OrderGetDouble(ORDER_SL), _Digits),
                          DoubleToString(OrderGetDouble(ORDER_TP), _Digits));
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      out += StringFormat("\n  #%I64u %s %s %.2f @ %s | $%+.2f | SL %s | TP %s", t, PositionGetString(POSITION_COMMENT),
                          (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL"), PositionGetDouble(POSITION_VOLUME),
                          DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits), PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP),
                          DoubleToString(PositionGetDouble(POSITION_SL), _Digits), DoubleToString(PositionGetDouble(POSITION_TP), _Digits));
   }
   if(g_set.on)
      out += StringFormat("\n  ชุด %s: R %.0f จุด | สูงสุด %+.0f | B %s%s", SysTag(g_set.ps.sys), PriceToPts(g_set.ps.R), PriceToPts(g_set.ps.mfe),
                          (g_set.ps.stage >= 2 ? "ไล่จี้" : (g_set.ps.stage == 1 ? "ทุน" : "SL แรก")), (g_set.ps.lock ? " | 🔒 ล็อกเป้า" : ""));
   return out;
}

void UpdateDashboard(int ts, datetime now, long msc) {
   if(!g_draw || !InpShowDashboard) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double floating = 0.0, worst = g_day.closed;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      double sl = PositionGetDouble(POSITION_SL), e = PositionGetDouble(POSITION_PRICE_OPEN), v = PositionGetDouble(POSITION_VOLUME);
      int    d  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(sl > 0.0) worst += d * (sl - e) * v * g_vpp;
   }
   double budget;
   string gate = DayGate(g_day, bal, budget);
   double lot2 = LotFor(budget, PtsToPrice(2000.0) + (ask - bid));
   string msg = StringFormat("=== 🛡️ 7-Lines Guard EA v1.00 (%s H1 | %s H2 | %s H3 | %s H4 | TP1 %.1fR + TP2 %.1fR | ทุน+%.0f ไล่จี้ %.0f | ถือ ≤ %d นาที | ตัดเร็ว %d วิ < %.0f) ===\n",
                             (g_en[1] ? "✅" : "⛔"), (g_en[2] ? "✅" : "⛔"), (g_en[3] ? "✅" : "⛔"), (g_en[4] ? "✅" : "⛔"),
                             InpTP1_R, InpTP2_R, InpBE_Pts, InpTrail_Pts, InpMaxHold_Min, InpFastCut_Sec, InpFastCut_Pts);
   msg += StringFormat("🎯 วันนี้ %s: ปิดแล้ว $%+.2f | ลอย $%+.2f | กรณีแย่สุด $%+.2f | เป้า $%.2f | พื้น $%+.2f | %s\n",
                       TimeToString(g_day.day, TIME_DATE), g_day.closed, floating, worst, InpDailyTarget_USD, DayFloor(g_day), DayPhase(g_day));
   msg += StringFormat("   ชุด %d ชนะ %d | แพ้ติด %d/%d | ทุน $%.2f | งบชุดถัดไป $%.2f%s | lot ถ้า SL 2,000 = %.2f\n",
                       g_day.sets, g_day.wins, g_day.consec, InpMaxConsecLoss, bal, budget, (gate == "" ? "" : " (" + gate + ")"), lot2);
   msg += g_c.zok ? StringFormat("Z สด : R %+.2f | S %+.2f | แท่งก่อน Z ที่ High %+.2f / Low %+.2f\n", g_c.zr, g_c.zs, g_c.p_zhi, g_c.p_zlo) : "Z สด : รอข้อมูล\n";
   msg += SysStatusText(msc) + "\n";
   msg += StringFormat("สเปรด %.0f / %.0f จุด | เวลาตลาด : %s\n", PriceToPts(ask - bid), InpMaxSpread_Pts, TimeStateText(ts, now));
   msg += "สถานะล่าสุด : " + g_last_status;
   if(InpShowReplay) msg += "\n" + ReplayStatsText();
   msg += PositionLines(bid, ask);
   if(msg != g_last_comment) { g_last_comment = msg; Comment(msg); }
}

//====================================================================
// 🔘 ปุ่ม H1-H4
//====================================================================
string SysGVName(int s) { return StringFormat("7LGD_%s_%I64d_H%d", _Symbol, InpMagic, s); }

void SysEnableInit() {
   int  r       = UninitializeReason();
   bool restore = (r == REASON_CHARTCHANGE || r == REASON_RECOMPILE || r == REASON_ACCOUNT);
   g_en[0] = false; g_en[1] = InpEnableH1; g_en[2] = InpEnableH2; g_en[3] = InpEnableH3; g_en[4] = InpEnableH4;
   for(int s = 1; s <= 4; s++) {
      if(restore && GlobalVariableCheck(SysGVName(s))) g_en[s] = (GlobalVariableGet(SysGVName(s)) > 0.5);
      GlobalVariableSet(SysGVName(s), g_en[s] ? 1.0 : 0.0);
   }
}

void DrawButtons() {
   if(!g_draw) return;
   for(int s = 1; s <= 4; s++) {
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
   if(s < 1 || s > 4) return;
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
   if(InpZ_Period < 3 || InpReplayDays < 1 || InpReplayDays > 60 || InpDailyTarget_USD <= 0.0 || InpDailyMaxLoss_USD <= 0.0 ||
      InpRiskPct <= 0.0 || InpMaxLot <= 0.0 || InpFloorKeepPct < 0.0 || InpFloorKeepPct > 100.0 || InpTargetLockBuf_USD < 0.0 ||
      InpMinSL_Pts <= 0.0 || InpMaxSL_Pts < InpMinSL_Pts || InpTP1_R <= 0.0 || InpTP2_R < 0.0 || InpTrail_Pts <= 0.0 ||
      InpH1_Sec < 0 || InpH3_Sec < 0 || InpH4_K2 < 1 || InpH4_WinSec < 1 || InpH2_Dist_Pts <= 0.0 || InpH2_SL_Pts <= 0.0 ||
      InpH2_Expire_Min < 1 || InpMaxHold_Min < 0 || InpFastCut_Sec < 0 || InpReplayBalance <= 0.0) {
      Print("❌ ค่า input ไม่ถูกต้อง (เป้า / ขาดทุน / เสี่ยง / lot > 0, ระยะ SL ต่ำสุด ≤ สูงสุด, วัน Replay 1-60, ...)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Print("❌ EA นี้ต้องใช้บัญชีแบบ Hedging (เปิดไม้ A / B แยกกัน)");
      return(INIT_FAILED);
   }
   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), tsz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_vpp = (tv > 0.0 && tsz > 0.0) ? tv / tsz : SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(g_vpp <= 0.0) g_vpp = 100.0;
   g_draw  = !(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints((ulong)MathMax(0.0, PtsToPrice(InpSlippage_Pts) / _Point));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);
   g_session_ok = BuildWeekBlocks();
   if(!g_session_ok) Print("⚠️ อ่านเวลา Session ของ Symbol ไม่ได้ — ปิดการกรองเวลาตลาด");
   if(StringFind(_Symbol, "XAU") < 0) PrintFormat("⚠️ EA ออกแบบสำหรับ XAUUSD แต่กำลังรันบน %s", _Symbol);
   CtxReset(g_c);
   WinReset(g_w);
   DayReset(g_day, 0);
   g_day_dirty = true; g_day_check = 0;
   for(int s = 0; s < 5; s++) g_next_try[s] = 0;
   g_set.on = false; g_set.tk[0] = 0; g_set.tk[1] = 0; g_set.last_mod = 0; g_set.next_try = 0;
   g_last_tick_msc = 0; g_tick_local = 0; g_del_retry = 0; g_heavy_ms = 0; g_blk_valid = false;
   g_last_comment = ""; g_last_status = "เริ่มทำงาน";
   ReplayReset();
   SysEnableInit();
   ObjectsDeleteAll(0, OBJ_PREFIX);
   DrawButtons();
   PrintFormat("🛡️ Guard EA: เป้า $%.2f/วัน | ขาดทุนสูงสุด $%.2f/วัน | เสี่ยง %.1f%%/ชุด | lot สูงสุด %.2f | มูลค่า $%.2f ต่อราคา 1.0 ต่อ 1 lot",
               InpDailyTarget_USD, InpDailyMaxLoss_USD, InpRiskPct, InpMaxLot, g_vpp);
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
   WinAdd(g_w, g_last_tick_msc, tk.bid);
   LiveCtxSync();
   if(g_c.ready) CtxTick(g_c, tk.bid, g_last_tick_msc);
   LiveDaySync();
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
   // 1. งานเทรดทุก 200 ms (แม้ไม่มี Tick): บังคับปิด / จัดการชุด / ลบ Stop / H1 H3 ครบเวลา
   LiveDaySync();
   if(ts == TS_CLOSING) CloseAllPositions();
   else if(bid > 0.0 && ask > 0.0) {
      LiveCtxSync();
      if(ts != TS_CLOSED) ManageLive(now, ts, msc);
      LiveSignals(ts, bid, ask, msc, false);
   }
   // 2. แสดงผลทุก 1 วินาที — ช่วงร้อน (H1 / H3 นับถอยหลัง, ถือชุดอยู่) ข้าม Tick Replay
   if(!g_draw || GetTickCount() - g_heavy_ms < 1000) return;
   g_heavy_ms = GetTickCount();
   bool hot = g_set.on || g_c.sb[0] || g_c.sb[1] || ((g_c.h1_arm[0] || g_c.h1_arm[1]) && !g_c.done[1]);
   if(!hot) ReplayStep();
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

// ดีลของ EA → สร้างสถานะวันใหม่ + ดีลเปิด = ระบบนั้นเปิดแล้วในแท่งนี้
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   g_day_dirty = true;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;
   int s = SysFromComment(HistoryDealGetString(trans.deal, DEAL_COMMENT));
   if(s > 0 && (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME) >= g_c.bar) g_c.done[s] = true;
}
//+------------------------------------------------------------------+
