//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Point-A Systems EA for XAUUSD (Z-Score volatility events)    |
//+------------------------------------------------------------------+
//
// 🎯 นิยามระบบ (v13)
//  จุด A = Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > 2.0 = ตลาดตื่น (การกระชาก / ข่าว / tick หนาแน่น) — ไม่ได้บอกทิศ แต่บอกว่าราคาจะวิ่งแรง
//  EA ออกแบบให้เอาตัวรอดจากจุด A ด้วย 6 ระบบ (เปิด/ปิดแยกด้วยปุ่มบนกราฟ, แต่ละระบบถือได้ครั้งละ 1 ไม้ และใช้สิทธิ์ได้ 1 ครั้งต่อจุด A)
//  (ประวัติการเปลี่ยนแปลงทุกเวอร์ชันอยู่ใน README.md)
//
// 📐 Z-Score (TF ของ Z, 20 แท่ง, รวมแท่งปัจจุบันที่ราคา Bid)
//  • Z_reg = (ราคา − เส้นถดถอยเชิงเส้น) / max(StdDev รอบเส้นถดถอย, 0.5 × StdDev ของส่วนต่างราคาต่อแท่ง)
//  • Z_SMA = (ราคา − SMA20) / StdDev20,  Z* = Z_SMA แบบไม่มีเพดาน = Z · √(n ÷ (n − 1 − Z²))
//  • σ ของทุกระบบ = SD20 (ตัวหาร Z_SMA) ณ ราคาปัจจุบัน
//
// 📍 จุด A (แยกฝั่งขึ้น / ลง): เริ่มเมื่อ Z ตัวใดตัวหนึ่ง > 2.0 ในทิศนั้น
//    จบเมื่อ Z ทั้งคู่กลับต่ำกว่า 1.0 หรือไม่มี Z > 2.0 ครบ 60 นาที → ยกเลิกคำสั่งรอทั้งหมด
//
// 📋 ระบบ (SELL = สวนฝั่งขึ้น / BUY = สวนฝั่งลง — ฝั่งลงกลับทิศทั้งหมด)
//  • T4 (เดิม): Z ตัวใดตัวหนึ่ง > 4.0 → สวนทันที, SL = High ของแท่ง + 500, TP 30,000, ไล่จี้แบบเดิม (เริ่ม 10,000 ห่าง 8,000)
//  • E1: จุด A เริ่ม → Buy Stop เหนือ High / Sell Stop ใต้ Low ของ 5 นาทีก่อนจุด A (± 200 จุด), โดนฝั่งไหนยกเลิกอีกฝั่ง, SL = อีกฝั่งของกรอบ
//  • N1: Sell Stop ที่ ยอด − 0.15σ (ขยับตามยอดใหม่), SL = ยอด + 500
//  • N2: ระบบเงา — Z > 2.5 เปิดไม้สวนแบบเงา (SL = High ของแท่ง + 500), เงาโดน SL ครบ 5 ครั้ง → ไม้จริงตามเทรนด์ (SL 1σ)
//        เงากำไรถึง 1R = นับพลาดใหม่
//  • N4: ราคาทำยอดใหม่ (≥ 100 จุดจากยอดที่ลงทะเบียน) แต่ tick/วิ 15 วิล่าสุด < 70% ของตอนยอดก่อน → สวน, SL = ยอด + 500
//  • N9: ระหว่างจุด A ราคาแตะระดับยอดของจุด A ในอดีต (High ของแท่งที่ Z ที่ High > 2.0, 5 วันย้อนหลัง, ห่าง ≤ 0.3σ) → สวน
//        SL = ระดับ + 0.3σ + 500
//  • คำสั่ง Stop ของ E1 / N1 ถือไว้ในตัว EA (ไม่ส่งไปโบรก) → ราคาข้ามระดับ = ส่ง Market ทันที (EA จริงกับ Tick Replay ตรงกัน)
//
// 📋 จัดการไม้ A-Survival (E1 / N1 / N2 / N4 / N9) — R = ระยะ SL ตอนเข้า
//  • กำไรถึง 1R → ปิด 50% + เลื่อน SL บังทุน → ส่วนที่เหลือ Chandelier: SL = ราคาดีที่สุดตั้งแต่เข้า ∓ 1σ (ขยับทางเดียว)
//  • ไม่ถึง 1R ภายใน 30 นาที → ปิด
//
// 🧱 ตัวกรอง: เวลาตลาด (ห้ามเข้า 1 ชม.แรกหลังเปิดสัปดาห์ / ปิดทุกไม้ 30 นาทีก่อนปิดสัปดาห์) + สเปรด + ข่าว USD High ±5 นาที
//
// 🧪 Tick Replay (บนกราฟ, ไม่ใช่ Strategy Tester): เล่นซ้ำ tick จริงด้วยกติกาเดียวกับ EA → มาร์กบนกราฟ + สรุปแยกระบบ + CSV
//
#property copyright   "Commander's Quant System"
#property version     "13.00"
#property description "จุด A (Z > 2.0 = ตลาดตื่น) + 6 ระบบ T4 / E1 / N1 / N2 / N4 / N9 สำหรับ XAUUSD (บัญชี Hedging)"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score / จุด A ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z_reg ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง
input double          InpA_Z               = 2.00;       // จุด A: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ (ฝั่งขึ้น +Z / ฝั่งลง −Z)
input double          InpA_EndZ            = 1.00;       // จุด A จบเมื่อ Z ทั้งคู่ (ทิศของการกระชาก) กลับต่ำกว่าค่านี้
input int             InpA_MaxIdle_Min     = 60;         // จุด A จบเมื่อไม่มี Z > จุด A ครบกี่นาที

input group "=== 2. ระบบ (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ) ==="
input bool            InpEnT4              = true;       // T4: Z ตัวใดตัวหนึ่ง > 4.0 → สวนทันที (ระบบเดิม)
input bool            InpEnE1              = true;       // E1: Stop 2 ฝั่ง (OCO) รอบกรอบก่อนจุด A
input bool            InpEnN1              = true;       // N1: Stop ใต้ยอด (ถอยแล้วสวน)
input bool            InpEnN2              = true;       // N2: ระบบเงา (สวนแบบเงาพลาดครบ → ตามเทรนด์)
input bool            InpEnN4              = true;       // N4: แรงหมด (ยอดใหม่แต่ tick ช้าลง → สวน)
input bool            InpEnN9              = true;       // N9: ความจำ (แตะระดับยอดของจุด A ในอดีต → สวน)

input group "=== 3. T4 (ระบบเดิม) ==="
input double          InpT4_Z              = 4.00;       // T4: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ → สวนทันที
input double          InpT4_Lot            = 0.04;       // T4: Lot
input double          InpSLPeak_Pts        = 500.0;      // ระยะ SL เหนือยอด (จุด): T4 / เงา N2 = High ของแท่ง, N1 / N4 = ยอด, N9 = ระดับ
input double          InpTP_Pts            = 30000.0;    // T4: Take Profit (จุด)
input double          InpTrailStart_Pts    = 10000.0;    // T4: เริ่มไล่จี้เมื่อกำไรถึง (จุด)
input double          InpTrailDist_Pts     = 8000.0;     // T4: ระยะโล่ห่างจากราคา (จุด)
input int             InpTrailInterval_Sec = 5;          // T4: ขยับโล่ทุกกี่วินาที (หลังเริ่มไล่จี้แล้ว)

input group "=== 4. ระบบใหม่ ==="
input double          InpSysLot            = 0.02;       // Lot ของ E1 / N1 / N2 / N4 / N9 (ต้องแบ่งปิดได้)
input int             InpE1_BoxMin         = 5;          // E1: กรอบ = High / Low ของกี่นาทีก่อนจุด A
input double          InpE1_Buffer_Pts     = 200.0;      // E1: ระยะ Stop เหนือ / ใต้กรอบ (จุด)
input double          InpN1_K              = 0.15;       // N1: Stop ห่างยอดกี่ σ
input double          InpN2_Z              = 2.50;       // N2: เปิดไม้เงาสวนเมื่อ Z ตัวใดตัวหนึ่ง > ค่านี้
input int             InpN2_Misses         = 5;          // N2: ไม้เงาโดน SL ครบกี่ครั้ง → ไม้จริงตามเทรนด์
input double          InpN2_SL_Sigma       = 1.00;       // N2: SL ของไม้ตามเทรนด์ห่างราคาเข้ากี่ σ
input double          InpN4_Ratio          = 0.70;       // N4: tick/วิ ตอนยอดใหม่ < ค่านี้ × ตอนยอดก่อนหน้า → สวน
input double          InpN4_NewHigh_Pts    = 100.0;      // N4: ยอดใหม่ต้องเกินยอดที่ลงทะเบียนไว้อย่างน้อย (จุด)
input int             InpN4_Rate_Sec       = 15;         // N4: นับ tick/วิ ย้อนหลังกี่วินาที
input int             InpN9_Days           = 5;          // N9: จำยอดของจุด A ย้อนหลังกี่วัน
input double          InpN9_Near_Sigma     = 0.30;       // N9: ราคาห่างระดับไม่เกินกี่ σ = แตะระดับ

input group "=== 5. จัดการไม้ A-Survival (E1 / N1 / N2 / N4 / N9) ==="
input double          InpPartial_R         = 1.00;       // กำไรถึงกี่ R → ปิดบางส่วน + เลื่อน SL บังทุน (R = ระยะ SL ตอนเข้า)
input double          InpPartial_Pct       = 50.0;       // ปิดบางส่วนกี่ %
input double          InpChand_Sigma       = 1.00;       // Chandelier (หลังปิดบางส่วน): SL = ราคาดีที่สุดตั้งแต่เข้า ∓ ค่านี้ × σ
input int             InpTimeCut_Min       = 30;         // ไม่ถึงจุดปิดบางส่วนภายในกี่นาที → ปิด (0 = ปิดกฎนี้)

input group "=== 6. ออเดอร์ / ตัวกรอง ==="
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์ (ต่อท้ายด้วยระบบ + R ใช้คืนค่าเมื่อรีสตาร์ท)
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input bool            InpNewsFilter        = true;       // งดเข้าไม้ช่วงข่าว High (ไม้ที่ถืออยู่รันต่อ, ใช้ไม่ได้ใน Tester)
input int             InpNewsBlock_Min     = 5;          // งดก่อน / หลังเวลาข่าวออกกี่นาที
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าว (กรอง + แสดง)

input group "=== 7. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowZLines        = true;       // แสดงเส้นแนวนอนระดับ Z ชุด Regression (± จุด A)
input bool            InpShowSmaZLines     = true;       // แสดงเส้นแนวนอนระดับ Z ชุด SMA20 (± จุด A)
input bool            InpShowLiveZ         = true;       // แสดงป้ายค่า Z สด ณ ราคาปัจจุบัน
input int             InpLiveZFontSize     = 11;         // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;         // ระยะห่างป้าย Z สดจากขอบขวาของกราฟ (พิกเซล)
input bool            InpShowBarZ          = true;       // แสดงป้ายค่า Z บนแท่งที่ถึงจุด A
input bool            InpShowFloatMark     = true;       // แสดงป้าย Z_float บนแท่งที่ราคาเปิดลอยพ้น SMA
input double          InpFloatMarkZ        = 1.00;       // ป้าย Z_float: แสดงเมื่อ Z_float > ค่านี้
input bool            InpFloatMarkLive     = true;       // ป้าย Z_float: แท่งปัจจุบันแสดงค่าเสมอตั้งแต่เปิดแท่ง (ไม่ถึงเกณฑ์ = สีเทา)
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย (สูงสุด 20,000)
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้จริง + ระยะห่างถึงปลายไส้เทียน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กสัญญาณที่ถูกตัวกรองทิ้ง
input bool            InpShowShadow        = true;       // Tick Replay: มาร์กไม้เงาของ N2 (○ เปิด / ✕ พลาด / ✓ ได้ 1R)
input bool            InpReplayCSV         = true;       // Tick Replay: บันทึกไม้ + ผล + ระยะกำไรระหว่างถือ ลง CSV (MQL5/Files)
input int             InpPostTrack_Min     = 60;         // Tick Replay: ติดตามต่อหลังเข้าไม้กี่นาที (แม้ไม้ปิดแล้ว)
input double          InpPostBackZ         = 1.00;       // Tick Replay: นับเวลาจนกว่า Z_SMA (ทิศของการกระชาก) กลับถึงค่านี้
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (ใช้ไม่ได้ใน Tester)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium บนกราฟด้วย (ไม่ใช้กรอง)

input group "=== 8. สี ==="
input color           InpClrZCenter        = clrGold;           // เส้นแนวนอน: เส้นกลาง Z = 0
input color           InpClrZSellLine      = clrOrangeRed;      // เส้นแนวนอน: จุด A ฝั่งขึ้น
input color           InpClrZBuyLine       = clrAqua;           // เส้นแนวนอน: จุด A ฝั่งลง
input color           InpClrSmaCenter      = clrDarkKhaki;      // เส้นแนวนอน SMA20: เส้นกลาง Z = 0
input color           InpClrSmaSellLine    = clrLightSalmon;    // เส้นแนวนอน SMA20: จุด A ฝั่งขึ้น
input color           InpClrSmaBuyLine     = clrPaleTurquoise;  // เส้นแนวนอน SMA20: จุด A ฝั่งลง
input color           InpClrLiveSell       = clrOrangeRed;      // ป้าย Z สด: ถึงจุด A ฝั่งขึ้น
input color           InpClrLiveBuy        = clrDeepSkyBlue;    // ป้าย Z สด: ถึงจุด A ฝั่งลง
input color           InpClrLiveNear       = clrGold;           // ป้าย Z สด: ใกล้จุด A
input color           InpClrLiveNormal     = clrSilver;         // ป้าย Z สด: ปกติ
input color           InpClrBarZSell       = clrOrangeRed;      // ป้าย Z บนแท่ง: ฝั่งขึ้น (เหนือแท่ง)
input color           InpClrBarZBuy        = clrDeepSkyBlue;    // ป้าย Z บนแท่ง: ฝั่งลง (ใต้แท่ง)
input color           InpClrBarZOther      = clrGray;           // ป้าย Z บนแท่ง: สีเทา (ป้าย Z_float ที่ไม่ถึงเกณฑ์)
input color           InpClrFloatMark      = clrMediumPurple;   // ป้าย Z_float (แท่งลอยพ้น SMA)
input color           InpClrEntrySell      = clrRed;            // มาร์กจุดเปิด SELL (ไม้จริง)
input color           InpClrEntryBuy       = clrLime;           // มาร์กจุดเปิด BUY (ไม้จริง)
input color           InpClrEntryGap       = clrYellow;         // เส้นประ + ตัวเลขระยะห่างถึงปลายไส้ (ไม้จริง)
input color           InpClrSimWin         = clrLimeGreen;      // มาร์กจำลอง: เส้นเข้า→ออก ไม้กำไร
input color           InpClrSimLoss        = clrTomato;         // มาร์กจำลอง: เส้นเข้า→ออก ไม้ขาดทุน
input color           InpClrSimBlocked     = clrDimGray;        // มาร์กจำลอง: สัญญาณที่ถูกตัวกรองทิ้ง
input color           InpClrShadow         = clrSlateGray;      // มาร์กจำลอง: ไม้เงาของ N2
input color           InpClrNewsLine       = clrMediumPurple;   // เส้นเวลาข่าว
input color           InpClrNewsZone       = C'45,35,70';       // แถบแท่งข่าว

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define TS_OPEN       0
#define TS_WAIT_OPEN  1
#define TS_CLOSING    2
#define TS_CLOSED     3

#define SYS_T4        0
#define SYS_E1        1
#define SYS_N1        2
#define SYS_N2        3
#define SYS_N4        4
#define SYS_N9        5
#define NSYS          6

#define RX_OPEN       0
#define RX_TP         1
#define RX_SL         2
#define RX_CUT        3
#define RX_TRAIL      4
#define RX_WEEK       5
#define RX_BE         6

const string OBJ_PREFIX     = "7LCEA_";
const string LINE_MAIN      = "7LCEA_MAIN";
const string LINE_SELL      = "7LCEA_SELL_Z";
const string LINE_BUY       = "7LCEA_BUY_Z";
const string LABEL_LIVE_Z   = "7LCEA_LIVE_Z";
const string LINE_SMA_MAIN  = "7LCEA_SMA_MAIN";
const string LINE_SMA_SELL  = "7LCEA_SMA_SELL_Z";
const string LINE_SMA_BUY   = "7LCEA_SMA_BUY_Z";
const string BTN_PREFIX     = "7LCEA_BTN_S";
const long   WEEK_SEC       = 604800;
const long   DAY_SEC        = 86400;
const long   MERGE_GAP_SEC  = 12 * 3600;   // ช่องว่าง session สั้นกว่านี้ (เช่นพักรายวัน) ถือว่าตลาดยังเปิด
const double NEAR_ZONE      = 0.5;         // ระยะ "ใกล้จุด A" สำหรับสีป้าย Z

struct WeekBlock {
   long s;   // วินาทีนับจากวันอาทิตย์ 00:00 (เวลาเซิร์ฟเวอร์)
   long e;
};

// แคชผลรวมของแท่งที่ปิดแล้ว (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct ZCache {
   bool   ok;
   double ref, sY, sXY, sYY, sD, sDD, last_close;
   double prev_zr, prev_zs;   // Z ตอนปิดแท่งล่าสุด
};

// ไม้ที่เปิดอยู่ (Tick Replay = ไม้จำลอง / EA จริง = เงาของไม้จริงที่ ticket)
struct VPos {
   bool   open;
   int    sys;          // SYS_*
   int    dir;          // −1 SELL / +1 BUY
   int    side;         // จุด A ฝั่งไหน (0 ขึ้น / 1 ลง, −1 = ไม่ทราบ)
   long   msc_in;
   double p_in, sl, sl0, tp;
   double lot, lot0;    // lot ที่ยังเปิด / lot ตอนเข้า
   double best;         // ราคาดีที่สุดตั้งแต่เข้า (ทิศของไม้)
   bool   partial;      // ปิดบางส่วนแล้ว
   bool   activated;    // T4: เริ่มไล่จี้แล้ว
   long   last_trail_sec;
   long   last_mod_sec; // EA จริง: แก้ SL ล่าสุด (กันส่งคำสั่งรัว)
   double zr, zs;       // Z ตอนเข้า
   long   a_msc;        // เวลาเริ่มจุด A
   double a_peak;       // ยอดของจุด A ตอนเข้า
   int    n2_miss;      // N2: ไม้เงาที่พลาดก่อนเข้า
   double info;         // N4: อัตรา tick ยอดใหม่ ÷ ยอดก่อน / N9: ระดับที่แตะ
   ulong  ticket;       // EA จริง
   int    rec;          // Tick Replay: index ใน g_rt
};

// สถานะจุด A ของแต่ละฝั่ง
struct AEvent {
   bool   active;
   long   start_msc;
   long   hot_msc;       // เวลาล่าสุดที่ Z > จุด A
   double peak;          // ราคายอด (Bid สูงสุดฝั่งขึ้น / ต่ำสุดฝั่งลง)
   long   peak_msc;
   double box_hi, box_lo;
   bool   done[NSYS];    // ระบบใช้สิทธิ์ในจุด A นี้แล้ว
   bool   e1_on;         // E1: Stop 2 ฝั่งรออยู่
   double e1_up, e1_dn;
   bool   n1_on;         // N1: Stop ใต้ยอดรออยู่
   double n1_px;
   bool   sh_open;       // N2: ไม้เงาเปิดอยู่
   double sh_px, sh_sl, sh_r;
   int    misses;        // N2: ไม้เงาพลาดติดกัน
   double n4_px;         // N4: ยอดที่ลงทะเบียนล่าสุด + tick/วิ ตอนนั้น
   double n4_rate;
};

// ไม้จำลองของ Tick Replay
struct RTrade {
   long   msc_in;
   int    sys, dir, side;
   double lot0, p_in, sl0, tp, zr, zs;
   long   a_msc;
   double a_peak;
   int    n2_miss;
   double info;
   bool   part;
   long   part_msc;
   double part_px, part_lot;
   double pnl_acc;       // Σ ส่วนต่างราคา × lot ของส่วนที่ปิดไปแล้ว
   double mfe, mae;      // กำไรสูงสุด / ติดลบสูงสุดระหว่างถือ (ราคา)
   double pa_sum, pa_ms, pa_fav;
   long   pa_msc;
   long   msc_out;
   double p_out;
   int    reason;
   double pnl;           // จุด (เทียบ lot ตอนเข้า)
   double usd;
   bool   drawn_final;
   double pt_zs_max, pt_adv, pt_fav, pt_back_sec;   // ติดตามต่อหลังเข้าไม้
   bool   pt_done;
};

struct RBlocked {
   long   msc;
   int    sys, dir;
   double price;
   string why;
};

struct RShadow {
   long   msc;
   int    side;
   int    kind;          // 0 เปิด / 1 พลาด (โดน SL) / 2 ได้ 1R
   double price;
   int    miss;
};

CTrade    trade;
double    g_pmult        = 1.0;
bool      g_draw         = true;
bool      g_en[NSYS];                  // เปิดใช้ระบบ (ปุ่มบนกราฟ)
color     g_sys_clr[NSYS];

// --- Z engine (แคชผลรวมของแท่งที่ปิดแล้ว, ค่าเลื่อนจุดอ้างอิง g_ref) ---
datetime  g_zbar_time    = 0;
bool      g_z_ready      = false;
double    g_ref          = 0.0;
bool      g_z_valid      = false;
double    g_z            = 0.0;   // Z สำหรับสีป้าย (ตัวที่ห่าง 0 มากกว่า)
double    g_z_reg        = 0.0;
double    g_center       = 0.0;   // ราคาเส้นกลาง Regression
double    g_sigma        = 0.0;   // ตัวหาร Regression ที่ใช้จริง
double    g_sma_mean     = 0.0;   // SMA20 (รวมแท่งปัจจุบัน)
double    g_sma_sd       = 0.0;   // StdDev20
bool      g_sigma_floor  = false;
double    g_z_sma        = 0.0;
double    g_prev_close_zr = 0.0;
double    g_prev_close_zs = 0.0;
bool      g_bar_changed  = false;

// --- แท่งปัจจุบัน / ข่าว ---
double    g_bar0_hi      = 0.0;
double    g_bar0_lo      = 0.0;
double    g_bar0_open    = 0.0;
double    g_bar0_fz      = 0.0;
double    g_bar0_fsma    = 0.0;
double    g_bar0_fsd     = 0.0;
datetime  g_news_times[];
string    g_news_names[];
datetime  g_news_loaded  = 0;
bool      g_news_ok      = false;

// --- Session ---
WeekBlock g_blocks[];
int       g_block_count  = 0;
bool      g_always_open  = false;
bool      g_session_ok   = false;
datetime  g_blk_open     = 0;
datetime  g_blk_close    = 0;
bool      g_blk_valid    = false;

// --- UI ---
long      g_last_tick_msc = 0;
string    g_last_status  = "เริ่มทำงาน";
string    g_last_comment = "";
double    g_line_main    = 0.0;
double    g_line_sell    = 0.0;
double    g_line_buy     = 0.0;
double    g_line_sma_main = 0.0;
double    g_line_sma_sell = 0.0;
double    g_line_sma_buy  = 0.0;
string    g_live_z_text  = "";
int       g_live_z_y     = -1;
string    g_lay_sig      = "";
datetime  g_mem_bar      = 0;      // EA จริง: แท่งตอนสร้างความจำ N9 ล่าสุด

// --- Tick Replay ---
RTrade     g_rt[];
RBlocked   g_rb[];
RShadow    g_sh[];
int        g_rb_drawn     = 0;
int        g_sh_drawn     = 0;
MqlRates   g_rr[];
double     g_rc[];                   // ราคาปิดของ g_rr (ความจำ N9)
int        g_rp_b         = -1;
datetime   g_rp_bar_t     = 0;
ZCache     g_rp_zc;
double     g_rp_hi        = 0.0;     // High / Low ของแท่งปัจจุบัน (จาก tick ที่เล่นมาแล้ว)
double     g_rp_lo        = 0.0;
double     g_rp_bid = 0.0, g_rp_ask = 0.0;
long       g_rp_msc       = 0;
bool       g_rp_have      = false;
bool       g_rp_init      = false;
bool       g_rp_caught    = false;
long       g_rp_cursor    = 0;
int        g_rp_retry     = 0;
int        g_rp_news_wait = 0;
long       g_rp_ticks     = 0;
string     g_rp_status    = "ยังไม่เริ่ม";
double     g_contract     = 100.0;
int        g_pt_from      = 0;
int        g_rp_csv_rows  = -1;
int        g_rp_csv_pt    = -1;

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

string SysTag(int s) {
   switch(s) {
      case SYS_T4: return "T4";
      case SYS_E1: return "E1";
      case SYS_N1: return "N1";
      case SYS_N2: return "N2";
      case SYS_N4: return "N4";
      case SYS_N9: return "N9";
   }
   return "?";
}

// ระบบจากคอมเมนต์ "7L-CNT N1 R1234" (−1 = อ่านไม่ได้)
int SysFromComment(string c) {
   for(int s = 0; s < NSYS; s++)
      if(StringFind(c, " " + SysTag(s) + " ") >= 0) return s;
   return -1;
}

// R (จุด) จากคอมเมนต์ (0 = ไม่มี)
double RFromComment(string c) {
   int p = StringFind(c, " R");
   return (p >= 0) ? StringToDouble(StringSubstr(c, p + 2)) : 0.0;
}

//====================================================================
// 🧮 Z
//====================================================================
double EffectiveZ(double zr, double zs) {
   return (MathAbs(zr) >= MathAbs(zs)) ? zr : zs;
}
// แท่งลอยตัว (ทิศของการกระชาก): fz = (ราคาเปิด − SMA ตอนเปิดแท่ง) ÷ SD20 → SELL ใช้ +fz / BUY ใช้ −fz (> 0 = พ้นเส้น SMA)
double ZFloat(int dir, double fz) { return (dir == -1) ? fz : -fz; }
// SMA / SD20 ตอนเปิดแท่งจากแคช Z (ราคาปิด 19 แท่งก่อน + ราคาเปิด) → fz (0 = คำนวณไม่ได้)
double FloatAtOpen(const ZCache &zc, double open, double &sma, double &sd) {
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   sma = 0.0; sd = 0.0;
   if(open <= 0.0 || !ZAtPrice(zc, open, zr, zs, fit, sig, fl, mn, ssd) || ssd <= 0.0) return 0.0;
   sma = zc.ref + mn;
   sd  = ssd;
   return (open - sma) / sd;
}
// Z* = Z_SMA แบบไม่มีเพดาน: ราคาปัจจุบันอยู่ในหน้าต่าง n ค่า → |Z_SMA| < √(n−1) เสมอ (n = 20 → 4.36) และอิ่มตัวใกล้เพดาน
//   Z* = (ราคา − ค่าเฉลี่ย n−1 แท่งก่อน) ÷ SD ของ n−1 แท่งนั้น = Z · √(n ÷ (n − 1 − Z²))  (Z 2.5 → 3.1, 3.0 → 4.2, 3.5 → 6.0, 4.0 → 10.3)
double ZStar(double z) {
   double n = (double)InpZ_Period, q = n - 1.0 - z * z;
   if(q <= 1.0e-6) return (z >= 0.0) ? 99.0 : -99.0;
   return z * MathSqrt(n / q);
}

//====================================================================
// 📐 Z-SCORE ENGINE (Regression Z)
//   x = 0..n-1 (แท่งปัจจุบัน x = n-1), y = ราคาปิด − g_ref
//   แท่งปิดถูกแคชเป็น Σy, Σxy, Σy², Σd, Σd² → ต่อ Tick คำนวณ O(1)
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
// สร้างแคชจากราคาปิด n แท่ง (c[0..n-1] เก่า→ใหม่, c[n-1] = แท่งที่เพิ่งปิด)
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
// Z ทั้งสองที่ราคา price โดยใช้แคช (fit / mn เป็นค่าสัมพัทธ์กับ zc.ref)
bool ZAtPrice(const ZCache &zc, double price, double &zr, double &zs,
              double &fit, double &sig, bool &fl, double &mn, double &ssd) {
   if(!zc.ok) return false;
   double n  = (double)InpZ_Period;
   double y  = price - zc.ref;
   double d0 = price - zc.last_close;
   return ComputeZ(zc.sY + y, zc.sXY + (n - 1.0) * y, zc.sYY + y * y, y,
                   zc.sD + d0, zc.sDD + d0 * d0, zr, zs, fit, sig, fl, mn, ssd);
}

ZCache g_zc;

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
   BuildZCache(c, g_zc);
   g_ref           = g_zc.ref;
   g_prev_close_zr = g_zc.prev_zr;
   g_prev_close_zs = g_zc.prev_zs;
   if(g_zbar_time != 0) g_bar_changed = true;

   // ช่วงแกว่งของแท่งปัจจุบัน
   g_bar0_hi = iHigh(_Symbol, InpZ_Timeframe, 0);
   g_bar0_lo = iLow (_Symbol, InpZ_Timeframe, 0);
   g_bar0_open = iOpen(_Symbol, InpZ_Timeframe, 0);
   g_bar0_fz   = FloatAtOpen(g_zc, g_bar0_open, g_bar0_fsma, g_bar0_fsd);

   g_zbar_time = t0;
   g_z_ready   = true;
   return true;
}
bool UpdateZ(double bid) {
   g_z_valid = false;
   if(!RefreshClosedBars()) return false;

   if(bid > g_bar0_hi)                    g_bar0_hi = bid;
   if(g_bar0_lo <= 0.0 || bid < g_bar0_lo) g_bar0_lo = bid;
   if(g_bar0_fsd <= 0.0) {   // ตอนขึ้นแท่งใหม่ยังอ่านราคาเปิดไม่ได้ → ลองใหม่ (ไม่ได้จริง ๆ ใช้ Bid แรกของแท่ง)
      if(g_bar0_open <= 0.0) g_bar0_open = iOpen(_Symbol, InpZ_Timeframe, 0);
      if(g_bar0_open <= 0.0) g_bar0_open = bid;
      g_bar0_fz = FloatAtOpen(g_zc, g_bar0_open, g_bar0_fsma, g_bar0_fsd);
   }

   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(!ZAtPrice(g_zc, bid, zr, zs, fit, sig, fl, mn, ssd)) return false;

   g_z_reg       = zr;
   g_z_sma       = zs;
   g_z           = EffectiveZ(zr, zs);
   g_sma_mean    = g_ref + mn;
   g_sma_sd      = ssd;
   g_center      = g_ref + fit;
   g_sigma       = sig;
   g_sigma_floor = fl;
   g_z_valid     = true;
   return true;
}

//====================================================================
// 📰 ปฏิทินข่าว (โหลดทุก 10 นาที, ใช้เวลาเซิร์ฟเวอร์)
//====================================================================
bool NewsEnabled() {
   return !MQLInfoInteger(MQL_TESTER);
}
bool NewsFilterOn() {
   return InpNewsFilter && InpNewsBlock_Min > 0 && NewsEnabled();
}
// โหลดข่าว High ของสกุลที่เลือก ตั้งแต่ต้นช่วง Tick Replay ถึง +24 ชม. (ทุก 10 นาที) — ใช้กรองการเข้าไม้ + แสดงบน Dashboard
void RefreshNews(datetime now) {
   if(!NewsEnabled() || (!InpNewsFilter && !InpShowNewsHistory)) return;
   if(g_news_loaded != 0 && now - g_news_loaded < 600) return;
   g_news_loaded = now;

   datetime from = now - (datetime)((InpReplayDays + 2) * DAY_SEC);
   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, from, now + (datetime)DAY_SEC, NULL, InpNewsCurrency)) {
      PrintFormat("⚠️ โหลดปฏิทินข่าวไม่สำเร็จ (error %d) — ลองใหม่ใน 10 วินาที", GetLastError());
      g_news_loaded = now - 590;
      return;
   }
   g_news_ok = true;
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   for(int i = 0; i < ArraySize(vals); i++) {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      // แทรกแบบเรียงเวลา (ใช้ค้นหาแบบแบ่งครึ่งใน NewsNear)
      int n = ArraySize(g_news_times);
      ArrayResize(g_news_times, n + 1);
      ArrayResize(g_news_names, n + 1);
      int k = n;
      while(k > 0 && g_news_times[k - 1] > vals[i].time) {
         g_news_times[k] = g_news_times[k - 1];
         g_news_names[k] = g_news_names[k - 1];
         k--;
      }
      g_news_times[k] = vals[i].time;
      g_news_names[k] = ev.name;
   }
}
// ข่าวที่อยู่ในช่วง ±InpNewsBlock_Min นาทีจากเวลา t → index ใน g_news_times (−1 = ไม่มี / ปิดตัวกรอง)
int NewsNear(datetime t) {
   if(!NewsFilterOn()) return -1;
   int  n  = ArraySize(g_news_times);
   long w  = (long)InpNewsBlock_Min * 60;
   int  lo = 0, hi = n;
   while(lo < hi) {   // ข่าวแรกที่เวลา ≥ t − w
      int mid = (lo + hi) / 2;
      if((long)g_news_times[mid] < (long)t - w) lo = mid + 1;
      else hi = mid;
   }
   if(lo < n && (long)g_news_times[lo] <= (long)t + w) return lo;
   return -1;
}
// แท่ง (TF ของ Z) ที่เริ่มเวลา bar_t มีข่าวออกในแท่งไหม
bool IsNewsBar(datetime bar_t, string &name) {
   if(!NewsEnabled() || bar_t == 0) return false;
   datetime bar_end = bar_t + (datetime)PeriodSeconds(InpZ_Timeframe);
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] >= bar_t && g_news_times[i] < bar_end) { name = g_news_names[i]; return true; }
   return false;
}
string NextNewsText(datetime now) {
   if(!InpShowNewsHistory && !InpNewsFilter) return "";
   if(!NewsEnabled()) return "📰 ปฏิทินข่าวใช้ไม่ได้ใน Tester (ไม่กรองข่าว)";
   int k = NewsNear(now);
   if(k >= 0) return StringFormat("🚫 งดเข้าไม้ช่วงข่าว: %s %s", TimeToString(g_news_times[k], TIME_MINUTES), g_news_names[k]);
   string name;
   if(IsNewsBar(CurrentZBarTime(), name)) return "📰 แท่งข่าว: " + name;
   datetime best = 0;
   string   best_name = "";
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] > now && (best == 0 || g_news_times[i] < best)) { best = g_news_times[i]; best_name = g_news_names[i]; }
   if(best == 0) return "📰 ไม่มีข่าว High ใน 24 ชม.";
   return StringFormat("📰 ข่าวถัดไป %s (อีก %s)", best_name, FormatDuration((long)(best - now)));
}

//====================================================================
// 🕒 เวลา / SESSION / ตัวกรอง
//====================================================================
// แท่ง (TF ของ Z) ที่เวลา t อยู่
datetime BarStartOf(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   return (per > 0) ? (datetime)((long)t - (long)t % per) : t;
}

// ตัวกรองตอนเข้าไม้ (ใช้ร่วมกัน) — เวลาตลาด + เพดานสเปรด + ข่าว
string EntryBlockReason(int ts, double bid, double ask, datetime t) {
   if(ts != TS_OPEN) return "เวลาตลาด";
   double sp = PriceToPts(ask - bid);
   if(sp > InpMaxSpread_Pts) return StringFormat("สเปรด %.0f > %.0f จุด", sp, InpMaxSpread_Pts);
   if(NewsNear(t) >= 0) return "ช่วงข่าว";
   return "";
}

bool TradeAllowed() {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
}
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
// หาช่วงตลาดเปิด (รายสัปดาห์) ที่ครอบเวลา t — ไม่ใช้แคช
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
   if(t <  o + (datetime)(InpNoTradeAfterOpen_Min * 60)) return TS_WAIT_OPEN;
   return TS_OPEN;
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
// ⚙️ ENGINE: จุด A + 6 ระบบ + จัดการไม้ (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//   ฝั่ง k: 0 = จุด A ขาขึ้น (สวน = SELL), 1 = ขาลง (สวน = BUY) — g = +1 / −1 แปลงทุกอย่างเป็นทิศของการกระชาก
//   คำสั่งที่ส่ง / แก้ / ปิด ทำผ่านฟังก์ชัน X* ที่ Tick Replay (จำลอง) และ EA จริง (ส่งคำสั่ง) เขียนต่างกัน
//====================================================================
class CEngine {
public:
   bool     m_live;
   long     m_now;           // msc ของรอบปัจจุบัน
   AEvent   m_ev[2];
   VPos     m_pos[];
   long     m_tk_msc[];      // tick ย้อนหลัง (กรอบ E1 / อัตรา tick N4)
   double   m_tk_bid[];
   int      m_tk_head;
   double   m_mem_px[];      // ความจำ N9: ระดับยอดของจุด A ในอดีต
   int      m_mem_side[];
   datetime m_mem_t[];       // เวลาแท่งของระดับ

   CEngine(void) { m_live = false; Reset(); }

   void Reset(void) {
      m_now = 0;
      m_tk_head = 0;
      ArrayResize(m_pos, 0);
      ArrayResize(m_tk_msc, 0);
      ArrayResize(m_tk_bid, 0);
      ArrayResize(m_mem_px, 0);
      ArrayResize(m_mem_side, 0);
      ArrayResize(m_mem_t, 0);
      ZeroMemory(m_ev[0]);
      ZeroMemory(m_ev[1]);
   }

   //--- คำสั่ง (เขียนทับใน Tick Replay / EA จริง) ---
   virtual bool XOpen(VPos &p)                                { return false; }
   virtual bool XClosePart(int i, double lot, double price)   { return false; }
   virtual bool XClose(int i, double price, int reason)       { return false; }
   virtual bool XModify(int i, double sl)                     { return false; }
   virtual void XBlocked(int sys, int dir, double price, string why) {}
   virtual void XShadow(int k, int kind, double price, int miss)     {}
   virtual void XTrack(int i, double prof)                    {}

   //--- tick ย้อนหลัง (เก็บ InpE1_BoxMin + 1 นาที) ---
   void TickAdd(long msc, double bid) {
      int n = ArraySize(m_tk_msc);
      ArrayResize(m_tk_msc, n + 1, 4096);
      ArrayResize(m_tk_bid, n + 1, 4096);
      m_tk_msc[n] = msc;
      m_tk_bid[n] = bid;
      long keep = (long)MathMax(InpE1_BoxMin + 1, 2) * 60000;
      while(m_tk_head < n && m_tk_msc[m_tk_head] < msc - keep) m_tk_head++;
      if(m_tk_head > 20000) {   // ย้ายส่วนที่ยังใช้มาไว้ต้นอาเรย์
         int m = n + 1 - m_tk_head;
         for(int q = 0; q < m; q++) { m_tk_msc[q] = m_tk_msc[m_tk_head + q]; m_tk_bid[q] = m_tk_bid[m_tk_head + q]; }
         ArrayResize(m_tk_msc, m, 4096);
         ArrayResize(m_tk_bid, m, 4096);
         m_tk_head = 0;
      }
   }

   // index ของ tick สุดท้ายที่เวลา ≤ t (−1 = ไม่มีข้อมูลย้อนไปถึง t)
   int TickAt(long t) {
      int lo = m_tk_head, hi = ArraySize(m_tk_msc) - 1, ans = -1;
      while(lo <= hi) {
         int mid = (lo + hi) / 2;
         if(m_tk_msc[mid] <= t) { ans = mid; lo = mid + 1; }
         else hi = mid - 1;
      }
      return ans;
   }

   // tick/วินาที ใน InpN4_Rate_Sec วินาทีล่าสุด
   double TickRate(long msc) {
      int k0 = TickAt(msc);
      if(k0 < 0) return 0.0;
      int k1 = TickAt(msc - (long)InpN4_Rate_Sec * 1000);
      if(k1 < 0) k1 = m_tk_head - 1;
      return (double)(k0 - k1) / InpN4_Rate_Sec;
   }

   // กรอบ E1: High / Low ของ tick ใน InpE1_BoxMin นาทีก่อน msc (ไม่มีข้อมูล = ราคาปัจจุบัน)
   void Box(long msc, double bid, double &hi, double &lo) {
      hi = bid;
      lo = bid;
      int a = TickAt(msc - (long)InpE1_BoxMin * 60000);
      int b = TickAt(msc - 1);
      a = (a < 0) ? m_tk_head : a + 1;
      for(int i = a; i <= b; i++) { hi = MathMax(hi, m_tk_bid[i]); lo = MathMin(lo, m_tk_bid[i]); }
   }

   //--- ความจำ N9 ---
   void MemAdd(datetime bar_t, int k, double px) {
      for(int i = ArraySize(m_mem_t) - 1; i >= 0; i--)
         if(m_mem_t[i] == bar_t && m_mem_side[i] == k) return;
      int n = ArraySize(m_mem_px);
      ArrayResize(m_mem_px, n + 1);
      ArrayResize(m_mem_side, n + 1);
      ArrayResize(m_mem_t, n + 1);
      m_mem_px[n] = px; m_mem_side[n] = k; m_mem_t[n] = bar_t;
   }

   void MemPrune(datetime oldest) {
      int n = ArraySize(m_mem_px), w = 0;
      for(int i = 0; i < n; i++) {
         if(m_mem_t[i] < oldest) continue;
         m_mem_px[w] = m_mem_px[i]; m_mem_side[w] = m_mem_side[i]; m_mem_t[w] = m_mem_t[i];
         w++;
      }
      if(w != n) { ArrayResize(m_mem_px, w); ArrayResize(m_mem_side, w); ArrayResize(m_mem_t, w); }
   }

   // แท่งปิด j (c[] = ราคาปิดเก่า→ใหม่): Z ที่ High > จุด A → จำ High (ฝั่งขึ้น) / Z ที่ Low < −จุด A → จำ Low (ฝั่งลง)
   void MemFromBar(const double &c[], int j, double hi, double lo, datetime t) {
      double zr, zs;
      if(ZForBarPrice(c, j, hi, zr, zs) && MathMax(zr, zs) > InpA_Z)   MemAdd(t, 0, hi);
      if(ZForBarPrice(c, j, lo, zr, zs) && MathMax(-zr, -zs) > InpA_Z) MemAdd(t, 1, lo);
   }

   //--- ไม้ ---
   bool HasOpen(int sys) {
      for(int i = ArraySize(m_pos) - 1; i >= 0; i--)
         if(m_pos[i].open && m_pos[i].sys == sys) return true;
      return false;
   }

   int CountOpen(void) {
      int c = 0;
      for(int i = ArraySize(m_pos) - 1; i >= 0; i--) if(m_pos[i].open) c++;
      return c;
   }

   // เปิดไม้ของระบบ sys → true = ใช้สิทธิ์ในจุด A นี้แล้ว (เปิดได้ หรือถูกตัวกรองทิ้ง)
   //   ไม่นับสิทธิ์: ปิดปุ่มอยู่ / ระบบนี้ถือไม้อยู่ / SL ผิดฝั่ง / ส่งคำสั่งไม่สำเร็จ
   bool Fire(int sys, int dir, int k, double bid, double ask, double sl, double tp, string block,
             double zr, double zs, double info) {
      if(!g_en[sys] || HasOpen(sys)) return false;
      double price = (dir == -1) ? bid : ask;
      if(block != "") { XBlocked(sys, dir, price, block); return true; }
      if((dir == -1 && sl <= price) || (dir == 1 && sl >= price)) return false;
      VPos p;
      ZeroMemory(p);
      p.open    = true;
      p.sys     = sys;
      p.dir     = dir;
      p.side    = k;
      p.msc_in  = m_now;
      p.p_in    = price;
      p.sl      = sl;
      p.sl0     = sl;
      p.tp      = tp;
      p.lot     = NormalizeLot(sys == SYS_T4 ? InpT4_Lot : InpSysLot);
      p.lot0    = p.lot;
      p.best    = price;
      p.zr      = zr;
      p.zs      = zs;
      p.a_msc   = m_ev[k].start_msc;
      p.a_peak  = m_ev[k].peak;
      p.n2_miss = m_ev[k].misses;
      p.info    = info;
      p.rec     = -1;
      if(!XOpen(p)) return false;
      int n = ArraySize(m_pos);
      ArrayResize(m_pos, n + 1);
      m_pos[n] = p;
      return true;
   }

   // SL ปัจจุบันดีกว่า (ขยับทางเดียว)
   bool Better(int i, double nsl) {
      if(m_pos[i].dir == -1) return (m_pos[i].sl <= 0.0 || nsl < m_pos[i].sl - _Point);
      return (nsl > m_pos[i].sl + _Point);
   }

   // เหตุผลเมื่อชน SL: ล็อกกำไรแล้ว = โล่ / บังทุน / SL
   int ExitReason(int i) {
      double lock = (m_pos[i].dir == -1) ? m_pos[i].p_in - m_pos[i].sl : m_pos[i].sl - m_pos[i].p_in;
      if(lock > _Point) return RX_TRAIL;
      if(m_pos[i].partial && lock > -_Point) return RX_BE;
      return RX_SL;
   }

   // T4: ไล่จี้แบบเดิม (กำไรถึง InpTrailStart_Pts → โล่ห่าง InpTrailDist_Pts ขยับทุก InpTrailInterval_Sec วินาที)
   void ManageT4(int i, long msc, double bid, double ask, double prof) {
      long sec   = msc / 1000;
      bool trail = false;
      if(!m_pos[i].activated) {
         if(prof >= PtsToPrice(InpTrailStart_Pts)) { m_pos[i].activated = true; trail = true; }
      }
      else if(sec - m_pos[i].last_trail_sec >= InpTrailInterval_Sec) trail = true;
      if(!trail) return;
      double dist = PtsToPrice(InpTrailDist_Pts);
      double nsl  = (m_pos[i].dir == -1) ? ask + dist : bid - dist;
      if(Better(i, nsl)) XModify(i, nsl);
      m_pos[i].last_trail_sec = sec;
   }

   // A-Survival: 1R → ปิดบางส่วน + บังทุน → Chandelier / ไม่ถึง 1R ใน InpTimeCut_Min นาที → ปิด
   void ManageA(int i, long msc, double bid, double ask, double sd, double prof) {
      int d = m_pos[i].dir;
      if(d == -1) m_pos[i].best = MathMin(m_pos[i].best, ask);
      else        m_pos[i].best = MathMax(m_pos[i].best, bid);
      if(!m_pos[i].partial) {
         double R = MathAbs(m_pos[i].p_in - m_pos[i].sl0);
         if(R > 0.0 && prof >= InpPartial_R * R) {
            double part = NormalizeLot(m_pos[i].lot * InpPartial_Pct / 100.0);
            bool   ok   = (part < m_pos[i].lot - 1e-9) ? XClosePart(i, part, (d == -1) ? ask : bid) : true;
            if(!ok) return;
            m_pos[i].partial = true;
            if(Better(i, m_pos[i].p_in)) XModify(i, m_pos[i].p_in);   // บังทุน
         }
         else if(InpTimeCut_Min > 0 && msc - m_pos[i].msc_in >= (long)InpTimeCut_Min * 60000)
            XClose(i, (d == -1) ? ask : bid, RX_CUT);
         return;
      }
      if(sd <= 0.0 || InpChand_Sigma <= 0.0) return;
      double nsl = (d == -1) ? m_pos[i].best + InpChand_Sigma * sd : m_pos[i].best - InpChand_Sigma * sd;
      if(Better(i, nsl)) XModify(i, nsl);
   }

   void Manage(long msc, double bid, double ask, double sd, int ts) {
      for(int i = ArraySize(m_pos) - 1; i >= 0; i--) {
         if(!m_pos[i].open) continue;
         int    d    = m_pos[i].dir;
         double px   = (d == -1) ? ask : bid;   // ราคาปิดไม้
         double prof = (d == -1) ? m_pos[i].p_in - ask : bid - m_pos[i].p_in;
         XTrack(i, prof);
         if(ts == TS_CLOSING) { XClose(i, px, RX_WEEK); continue; }
         if(!m_live) {   // Tick Replay: SL / TP (EA จริงโบรกปิดให้)
            bool sl_hit = (m_pos[i].sl > 0.0) && ((d == -1) ? ask >= m_pos[i].sl : bid <= m_pos[i].sl);
            bool tp_hit = (m_pos[i].tp > 0.0) && ((d == -1) ? ask <= m_pos[i].tp : bid >= m_pos[i].tp);
            if(sl_hit) { XClose(i, px, ExitReason(i)); continue; }
            if(tp_hit) { XClose(i, m_pos[i].tp, RX_TP); continue; }
         }
         if(m_pos[i].sys == SYS_T4) ManageT4(i, msc, bid, ask, prof);
         else                       ManageA(i, msc, bid, ask, sd, prof);
      }
      int n = ArraySize(m_pos), w = 0;   // ลบไม้ที่ปิดแล้ว
      for(int i = 0; i < n; i++) {
         if(!m_pos[i].open) continue;
         if(w != i) m_pos[w] = m_pos[i];
         w++;
      }
      if(w != n) ArrayResize(m_pos, w);
   }

   //--- จุด A ฝั่ง k + สัญญาณของทุกระบบ ---
   void SideStep(AEvent &e, int k, long msc, double bid, double ask, double zr, double zs, double sd,
                 double bar_hi, double bar_lo, string block) {
      double g  = (k == 0) ? 1.0 : -1.0;
      int    fd = (k == 0) ? -1 : 1;            // ทิศสวน
      double gz = MathMax(g * zr, g * zs);      // Z ตัวที่มากกว่า (ทิศของการกระชาก)
      double pt = PtsToPrice(InpSLPeak_Pts);
      double hi = (bar_hi > 0.0) ? MathMax(bar_hi, bid) : bid;
      double lo = (bar_lo > 0.0) ? MathMin(bar_lo, bid) : bid;

      // 1) เริ่ม / จบจุด A
      if(!e.active) {
         if(gz <= InpA_Z) return;
         ZeroMemory(e);
         e.active    = true;
         e.start_msc = msc;
         e.hot_msc   = msc;
         e.peak      = bid;
         e.peak_msc  = msc;
         e.n4_px     = bid;
         e.n4_rate   = TickRate(msc);
         Box(msc, bid, e.box_hi, e.box_lo);
         if(g_en[SYS_E1]) {
            e.e1_on = true;
            e.e1_up = e.box_hi + PtsToPrice(InpE1_Buffer_Pts);
            e.e1_dn = e.box_lo - PtsToPrice(InpE1_Buffer_Pts);
         }
         if(g_en[SYS_N1]) { e.n1_on = true; e.n1_px = e.peak - g * InpN1_K * sd; }
      }
      else {
         if(gz > InpA_Z) e.hot_msc = msc;
         if(gz < InpA_EndZ || msc - e.hot_msc > (long)InpA_MaxIdle_Min * 60000) { ZeroMemory(e); return; }
      }

      // 2) ยอดใหม่ (N1 ขยับตาม) + N4: ยอดใหม่เกินยอดที่ลงทะเบียน ≥ InpN4_NewHigh_Pts → เทียบอัตรา tick
      if(g * (bid - e.peak) > 0.0) {
         e.peak     = bid;
         e.peak_msc = msc;
         if(e.n1_on) e.n1_px = e.peak - g * InpN1_K * sd;
      }
      bool   n4_sig   = false;
      double n4_ratio = 0.0;
      if(g * (bid - e.n4_px) >= PtsToPrice(InpN4_NewHigh_Pts)) {
         double r = TickRate(msc);
         if(e.n4_rate > 0.0) { n4_ratio = r / e.n4_rate; n4_sig = (n4_ratio < InpN4_Ratio); }
         e.n4_px   = bid;
         e.n4_rate = r;
      }

      // 3) T4: Z ตัวใดตัวหนึ่ง > InpT4_Z → สวนทันที (SL = High / Low ของแท่ง ± 500, TP 30,000)
      if(!e.done[SYS_T4] && gz > InpT4_Z) {
         double sl  = (fd == -1) ? hi + pt : lo - pt;
         double tpd = PtsToPrice(InpTP_Pts);
         double tp  = (fd == -1) ? bid - tpd : ask + tpd;
         if(Fire(SYS_T4, fd, k, bid, ask, sl, tp, block, zr, zs, 0.0)) e.done[SYS_T4] = true;
      }

      // 4) E1: Stop 2 ฝั่งรอบกรอบ — โดนฝั่งไหนยกเลิกอีกฝั่ง, SL = อีกฝั่งของกรอบ
      if(e.e1_on) {
         int    d  = 0;
         double sl = 0.0;
         if(ask >= e.e1_up)      { d =  1; sl = e.e1_dn; }
         else if(bid <= e.e1_dn) { d = -1; sl = e.e1_up; }
         if(d != 0) {
            e.e1_on = false;
            if(!e.done[SYS_E1] && Fire(SYS_E1, d, k, bid, ask, sl, 0.0, block, zr, zs, 0.0)) e.done[SYS_E1] = true;
         }
      }

      // 5) N1: Stop ห่างยอด InpN1_K σ (ขยับตามยอดใหม่), SL = ยอด ± 500
      if(e.n1_on && !e.done[SYS_N1]) {
         bool hit = (fd == -1) ? (bid <= e.n1_px) : (ask >= e.n1_px);
         if(hit) {
            e.n1_on = false;
            if(Fire(SYS_N1, fd, k, bid, ask, e.peak + g * pt, 0.0, block, zr, zs, 0.0)) e.done[SYS_N1] = true;
         }
      }

      // 6) N2: ระบบเงา — เงาโดน SL = พลาด +1 / เงากำไรถึง 1R = นับใหม่ / พลาดครบ → ไม้จริงตามเทรนด์
      if(g_en[SYS_N2]) {
         if(e.sh_open) {
            double px   = (fd == -1) ? ask : bid;
            bool   hit  = (fd == -1) ? (ask >= e.sh_sl) : (bid <= e.sh_sl);
            double prof = (fd == -1) ? e.sh_px - ask : bid - e.sh_px;
            if(hit)                                  { e.sh_open = false; e.misses++;    XShadow(k, 1, px, e.misses); }
            else if(prof >= InpPartial_R * e.sh_r)   { e.sh_open = false; e.misses = 0;  XShadow(k, 2, px, 0); }
         }
         if(e.misses >= InpN2_Misses && !e.done[SYS_N2]) {
            int    d  = -fd;
            double sl = (d == 1) ? ask - InpN2_SL_Sigma * sd : bid + InpN2_SL_Sigma * sd;
            if(Fire(SYS_N2, d, k, bid, ask, sl, 0.0, block, zr, zs, (double)e.misses)) e.done[SYS_N2] = true;
            e.misses = 0;
         }
         if(!e.sh_open && !e.done[SYS_N2] && gz > InpN2_Z) {
            e.sh_open = true;
            e.sh_px   = (fd == -1) ? bid : ask;
            e.sh_sl   = (fd == -1) ? hi + pt : lo - pt;
            e.sh_r    = MathAbs(e.sh_sl - e.sh_px);
            XShadow(k, 0, e.sh_px, e.misses);
         }
      }

      // 7) N4: ยอดใหม่แต่ tick ช้าลง → สวน, SL = ยอด ± 500
      if(n4_sig && !e.done[SYS_N4])
         if(Fire(SYS_N4, fd, k, bid, ask, e.peak + g * pt, 0.0, block, zr, zs, n4_ratio)) e.done[SYS_N4] = true;

      // 8) N9: แตะระดับยอดของจุด A ในอดีต (แท่งที่ปิดก่อนจุด A นี้เริ่ม, ย้อนหลัง InpN9_Days วัน) → สวน
      if(!e.done[SYS_N9] && g_en[SYS_N9] && !HasOpen(SYS_N9) && sd > 0.0) {
         double   near = InpN9_Near_Sigma * sd;
         datetime lim  = (datetime)(e.start_msc / 1000) - (datetime)PeriodSeconds(InpZ_Timeframe);
         datetime old  = (datetime)(msc / 1000) - (datetime)(InpN9_Days * DAY_SEC);
         for(int i = 0; i < ArraySize(m_mem_px); i++) {
            if(m_mem_side[i] != k || m_mem_t[i] > lim || m_mem_t[i] < old) continue;
            if(MathAbs(bid - m_mem_px[i]) > near) continue;
            double sl = (fd == -1) ? MathMax(m_mem_px[i] + near, bid) + pt : MathMin(m_mem_px[i] - near, bid) - pt;
            if(Fire(SYS_N9, fd, k, bid, ask, sl, 0.0, block, zr, zs, m_mem_px[i])) e.done[SYS_N9] = true;
            break;
         }
      }
   }

   // ทุก tick (new_tick = true) และทุก 1 วินาที: จัดการไม้ → จุด A + สัญญาณทั้ง 2 ฝั่ง
   void Step(long msc, double bid, double ask, bool new_tick, const ZCache &zc,
             double bar_hi, double bar_lo, int ts, string block) {
      m_now = msc;
      if(new_tick) TickAdd(msc, bid);
      double zr = 0.0, zs = 0.0, fit, sig, mn, sd = 0.0;
      bool   fl;
      bool   zok = ZAtPrice(zc, bid, zr, zs, fit, sig, fl, mn, sd) && sd > 0.0;
      Manage(msc, bid, ask, zok ? sd : 0.0, ts);
      if(!zok) return;
      SideStep(m_ev[0], 0, msc, bid, ask, zr, zs, sd, bar_hi, bar_lo, block);
      SideStep(m_ev[1], 1, msc, bid, ask, zr, zs, sd, bar_hi, bar_lo, block);
   }
};

//====================================================================
// 🧪 TICK REPLAY ENGINE (ไม้จำลอง → g_rt)
//====================================================================
void ProfitAvgAdd(int i, long msc, double fav) {
   if(msc > g_rt[i].pa_msc) {
      double dt = (double)(msc - g_rt[i].pa_msc);
      g_rt[i].pa_sum += g_rt[i].pa_fav * dt;
      g_rt[i].pa_ms  += dt;
   }
   g_rt[i].pa_msc = msc;
   g_rt[i].pa_fav = fav;
}

double ProfitAvgPts(int i) {
   return PriceToPts(g_rt[i].pa_ms > 0.0 ? g_rt[i].pa_sum / g_rt[i].pa_ms : g_rt[i].pa_fav);
}

class CReplay : public CEngine {
public:
   virtual bool XOpen(VPos &p) {
      int i = ArraySize(g_rt);
      ArrayResize(g_rt, i + 1, 256);
      ZeroMemory(g_rt[i]);
      g_rt[i].msc_in   = p.msc_in;
      g_rt[i].sys      = p.sys;
      g_rt[i].dir      = p.dir;
      g_rt[i].side     = p.side;
      g_rt[i].lot0     = p.lot;
      g_rt[i].p_in     = p.p_in;
      g_rt[i].sl0      = p.sl;
      g_rt[i].tp       = p.tp;
      g_rt[i].zr       = p.zr;
      g_rt[i].zs       = p.zs;
      g_rt[i].a_msc    = p.a_msc;
      g_rt[i].a_peak   = p.a_peak;
      g_rt[i].n2_miss  = p.n2_miss;
      g_rt[i].info     = p.info;
      g_rt[i].pa_msc   = p.msc_in;
      g_rt[i].reason   = RX_OPEN;
      g_rt[i].pt_zs_max   = (p.side == 1) ? -p.zs : p.zs;
      g_rt[i].pt_back_sec = -1.0;
      p.rec = i;
      return true;
   }

   virtual bool XClosePart(int i, double lot, double price) {
      int    r    = m_pos[i].rec;
      double diff = (m_pos[i].dir == -1) ? m_pos[i].p_in - price : price - m_pos[i].p_in;
      g_rt[r].part     = true;
      g_rt[r].part_msc = m_now;
      g_rt[r].part_px  = price;
      g_rt[r].part_lot = lot;
      g_rt[r].pnl_acc += diff * lot;
      g_rt[r].usd     += diff * lot * g_contract;
      m_pos[i].lot    -= lot;
      return true;
   }

   virtual bool XClose(int i, double price, int reason) {
      int    r    = m_pos[i].rec;
      double diff = (m_pos[i].dir == -1) ? m_pos[i].p_in - price : price - m_pos[i].p_in;
      ProfitAvgAdd(r, m_now, diff);
      g_rt[r].usd    += diff * m_pos[i].lot * g_contract;
      g_rt[r].pnl     = PriceToPts((g_rt[r].pnl_acc + diff * m_pos[i].lot) / MathMax(g_rt[r].lot0, 1e-9));
      g_rt[r].msc_out = m_now;
      g_rt[r].p_out   = price;
      g_rt[r].reason  = reason;
      m_pos[i].open   = false;
      return true;
   }

   virtual bool XModify(int i, double sl) { m_pos[i].sl = sl; return true; }

   virtual void XBlocked(int sys, int dir, double price, string why) {
      int k = ArraySize(g_rb);
      ArrayResize(g_rb, k + 1);
      g_rb[k].msc = m_now; g_rb[k].sys = sys; g_rb[k].dir = dir; g_rb[k].price = price; g_rb[k].why = why;
   }

   virtual void XShadow(int k, int kind, double price, int miss) {
      if(!InpShowShadow) return;
      int n = ArraySize(g_sh);
      ArrayResize(g_sh, n + 1, 256);
      g_sh[n].msc = m_now; g_sh[n].side = k; g_sh[n].kind = kind; g_sh[n].price = price; g_sh[n].miss = miss;
   }

   virtual void XTrack(int i, double prof) {
      int r = m_pos[i].rec;
      if(prof > g_rt[r].mfe) g_rt[r].mfe = prof;
      if(prof < g_rt[r].mae) g_rt[r].mae = prof;
      ProfitAvgAdd(r, m_now, prof);
   }
};

//====================================================================
// 💼 EA ENGINE (ส่งคำสั่งจริง) — SL / TP อยู่ที่โบรก, ไม้ที่โบรกปิดแล้วลบออกใน LiveSync
//====================================================================
class CLive : public CEngine {
public:
   datetime m_retry;    // ส่งคำสั่งเปิดไม่สำเร็จ → ลองใหม่หลังเวลานี้
   datetime m_close_retry;

   CLive(void) { m_live = true; m_retry = 0; m_close_retry = 0; }

   virtual bool XOpen(VPos &p) {
      datetime now = ServerNow();
      if(now < m_retry) return false;
      if(!TradeAllowed()) { g_last_status = SysTag(p.sys) + " มีสัญญาณแต่ปิด Algo Trading อยู่"; m_retry = now + 5; return false; }
      double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = (p.dir == -1) ? MathMax(p.sl, ask + stops + _Point) : MathMin(p.sl, bid - stops - _Point);
      sl = ND(sl);
      double tp    = (p.tp > 0.0) ? ND(p.tp) : 0.0;
      string cmt   = StringFormat("%s %s R%.0f", InpOrderComment, SysTag(p.sys), PriceToPts(MathAbs(p.p_in - sl)));
      bool   ok    = (p.dir == -1) ? trade.Sell(p.lot, _Symbol, bid, sl, tp, cmt) : trade.Buy(p.lot, _Symbol, ask, sl, tp, cmt);
      uint   rc    = trade.ResultRetcode();
      if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL)) {
         m_retry = now + 1;
         g_last_status = StringFormat("%s %s ส่งคำสั่งไม่สำเร็จ: %u %s", SysTag(p.sys), (p.dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
         PrintFormat("❌ %s", g_last_status);
         return false;
      }
      p.ticket = trade.ResultOrder();
      if(trade.ResultPrice() > 0.0) p.p_in = trade.ResultPrice();
      p.sl  = sl;
      p.sl0 = sl;
      g_last_status = StringFormat("✅ เปิด %s %s %.2f lot @ %s | SL %s (R %.0f จุด)%s", SysTag(p.sys), (p.dir == -1 ? "SELL" : "BUY"), p.lot,
                                   DoubleToString(p.p_in, _Digits), DoubleToString(sl, _Digits), PriceToPts(MathAbs(p.p_in - sl)),
                                   (tp > 0.0 ? " | TP " + DoubleToString(tp, _Digits) : ""));
      Print(g_last_status);
      return true;
   }

   // ไม้ที่โบรกปิดไปแล้ว (SL / TP) → ปิดในรายการทันที ไม่ส่งคำสั่งซ้ำ
   bool Gone(int i) {
      if(PositionSelectByTicket(m_pos[i].ticket)) return false;
      m_pos[i].open = false;
      return true;
   }

   virtual bool XClosePart(int i, double lot, double price) {
      if(Gone(i)) return false;
      datetime now = ServerNow();
      if(now < m_close_retry) return false;
      if(!trade.PositionClosePartial(m_pos[i].ticket, lot)) {
         m_close_retry = now + 1;
         PrintFormat("⚠️ ปิดบางส่วน #%I64u ไม่สำเร็จ: %u %s", m_pos[i].ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         return false;
      }
      m_pos[i].lot -= lot;
      g_last_status = StringFormat("💰 %s #%I64u ปิดบางส่วน %.2f lot ที่ %.1fR → บังทุน", SysTag(m_pos[i].sys), m_pos[i].ticket, lot, InpPartial_R);
      Print(g_last_status);
      return true;
   }

   virtual bool XClose(int i, double price, int reason) {
      if(Gone(i)) return false;
      datetime now = ServerNow();
      if(now < m_close_retry) return false;
      if(!trade.PositionClose(m_pos[i].ticket)) {
         m_close_retry = now + 1;
         PrintFormat("❌ ปิด #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", m_pos[i].ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         return false;
      }
      g_last_status = StringFormat("🛑 ปิด %s #%I64u (%s)", SysTag(m_pos[i].sys), m_pos[i].ticket, ReplayReasonName(reason));
      Print(g_last_status);
      m_pos[i].open = false;
      return true;
   }

   // แก้ SL (ไม่เกินวินาทีละครั้งต่อไม้ + เคารพ Stops / Freeze Level)
   virtual bool XModify(int i, double sl) {
      long sec = m_now / 1000;
      if(sec - m_pos[i].last_mod_sec < 1 || Gone(i)) return false;
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
      double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
      double nsl    = ND(sl);
      if(m_pos[i].dir == -1) {
         if(nsl - ask < stops) return false;
         if(m_pos[i].sl > 0.0 && m_pos[i].sl - ask <= freeze) return false;
      } else {
         if(bid - nsl < stops) return false;
         if(m_pos[i].sl > 0.0 && bid - m_pos[i].sl <= freeze) return false;
      }
      m_pos[i].last_mod_sec = sec;
      if(!trade.PositionModify(m_pos[i].ticket, nsl, m_pos[i].tp)) {
         PrintFormat("⚠️ ขยับ SL #%I64u ไม่สำเร็จ: %u %s", m_pos[i].ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         return false;
      }
      m_pos[i].sl = nsl;
      return true;
   }

   virtual void XBlocked(int sys, int dir, double price, string why) {
      g_last_status = StringFormat("%s %s มีสัญญาณแต่ติด: %s → ทิ้งสัญญาณ", SysTag(sys), (dir == -1 ? "SELL" : "BUY"), why);
   }
};

CReplay g_rp;
CLive   g_lv;

// EA จริง: ลบไม้ที่โบรกปิดแล้ว + อัปเดต SL / lot จากโบรก
void LiveSync() {
   int n = ArraySize(g_lv.m_pos), w = 0;
   for(int i = 0; i < n; i++) {
      if(!g_lv.m_pos[i].open || !PositionSelectByTicket(g_lv.m_pos[i].ticket)) continue;
      g_lv.m_pos[i].sl  = PositionGetDouble(POSITION_SL);
      g_lv.m_pos[i].tp  = PositionGetDouble(POSITION_TP);
      g_lv.m_pos[i].lot = PositionGetDouble(POSITION_VOLUME);
      if(w != i) g_lv.m_pos[w] = g_lv.m_pos[i];
      w++;
   }
   if(w != n) ArrayResize(g_lv.m_pos, w);
}

// EA จริง: คืนไม้ที่ถืออยู่เมื่อรีสตาร์ท (ระบบ / R จากคอมเมนต์)
void LiveRestore() {
   ArrayResize(g_lv.m_pos, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      int    sys = SysFromComment(cmt);
      if(sys < 0) continue;
      VPos p;
      ZeroMemory(p);
      p.open   = true;
      p.sys    = sys;
      p.dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      p.side   = -1;
      p.ticket = ticket;
      p.msc_in = PositionGetInteger(POSITION_TIME_MSC);
      p.p_in   = PositionGetDouble(POSITION_PRICE_OPEN);
      p.sl     = PositionGetDouble(POSITION_SL);
      p.tp     = PositionGetDouble(POSITION_TP);
      p.lot    = PositionGetDouble(POSITION_VOLUME);
      p.lot0   = NormalizeLot(sys == SYS_T4 ? InpT4_Lot : InpSysLot);
      double r = RFromComment(cmt);
      p.sl0    = (r > 0.0) ? p.p_in - p.dir * PtsToPrice(r) : p.sl;
      p.best   = (p.dir == -1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      p.partial   = (p.lot < p.lot0 - 1e-9);
      p.activated = (p.sl > 0.0) && ((p.dir == -1) ? p.sl < p.p_in : p.sl > p.p_in);
      p.rec    = -1;
      int n = ArraySize(g_lv.m_pos);
      ArrayResize(g_lv.m_pos, n + 1);
      g_lv.m_pos[n] = p;
   }
   if(ArraySize(g_lv.m_pos) > 0) PrintFormat("♻️ คืนไม้ที่ถืออยู่ %d ไม้ (จัดการต่อตามระบบในคอมเมนต์)", ArraySize(g_lv.m_pos));
}

// EA จริง: ความจำ N9 จากแท่งปิด InpN9_Days วันล่าสุด (สร้างใหม่ทุกแท่ง)
void LiveMemRebuild() {
   datetime t0 = CurrentZBarTime();
   if(t0 == 0 || t0 == g_mem_bar) return;
   int n       = InpZ_Period;
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int cnt     = InpN9_Days * per_day + n + 2;
   MqlRates r[];
   int got = CopyRates(_Symbol, InpZ_Timeframe, 1, cnt, r);
   if(got <= n) return;
   double c[];
   ArrayResize(c, got);
   for(int i = 0; i < got; i++) c[i] = r[i].close;
   for(int j = n - 1; j < got; j++) g_lv.MemFromBar(c, j, r[j].high, r[j].low, r[j].time);
   g_lv.MemPrune(ServerNow() - (datetime)(InpN9_Days * DAY_SEC));
   g_mem_bar = t0;
}

//====================================================================
// 🏷️ ป้ายค่า Z บนแท่งที่ถึงจุด A (TF ของ Z)
//====================================================================
string   g_zl_names[];
datetime g_zl_times[];
datetime g_barz_bar = 0;

void RememberBarZLabel(string name, datetime t) {
   for(int i = ArraySize(g_zl_names) - 1; i >= 0; i--)
      if(g_zl_names[i] == name) return;
   int n = ArraySize(g_zl_names);
   ArrayResize(g_zl_names, n + 1);
   ArrayResize(g_zl_times, n + 1);
   g_zl_names[n] = name;
   g_zl_times[n] = t;
}

// วาด/ลบป้าย Z ของแท่งเวลา t — zr/zs = Regression/SMA Z ที่ High [0] และ Low [1]
void SetBarZLabels(datetime t, double hi, double lo, const double &zr[], const double &zs[], const bool &ok[]) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)t);
   for(int side = 0; side < 2; side++) {
      string name = OBJ_PREFIX + (side == 0 ? "ZL_S_" : "ZL_B_") + ts;
      double g    = (side == 0) ? 1.0 : -1.0;
      bool   hit_r = ok[side] && g * zr[side] > InpA_Z;
      bool   hit_s = ok[side] && g * zs[side] > InpA_Z;
      if(!(hit_r || hit_s)) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }
      double gz    = MathMax(g * zr[side], g * zs[side]);
      double price = (side == 0) ? (hi + off) : (lo - off);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_LOWER : ANCHOR_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         RememberBarZLabel(name, t);
      }
      ObjectSetInteger(0, name, OBJPROP_TIME, t);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, ND(price));
      ObjectSetInteger(0, name, OBJPROP_COLOR, (side == 0) ? InpClrBarZSell : InpClrBarZBuy);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("R%+.2f | S%+.2f | S*%+.1f", zr[side], zs[side], ZStar(zs[side])));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s (Z* %+.2f ไม่มีเพดาน) | %s",
                                   TimeToString(t, TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                   zr[side], (hit_r ? " ✓" : ""), zs[side], (hit_s ? " ✓" : ""), ZStar(zs[side]),
                                   (gz > InpT4_Z ? "ถึง T4" : "จุด A")));
   }
}

// ป้าย Z_float ของแท่งเวลา t: ราคาเปิดลอยพ้น SMA (ตอนเปิดแท่ง) เกิน InpFloatMarkZ → SELL ป้ายใต้ Low / BUY ป้ายเหนือ High
//   always = แท่งปัจจุบัน: แสดงค่าฝั่งที่ราคาเปิดอยู่เสมอ (ไม่ถึงเกณฑ์ = สีเทา)
void SetBarFloatLabel(datetime t, double hi, double lo, double open, double sma, double sd, bool always) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)t);
   for(int side = 0; side < 2; side++) {
      int    dir  = (side == 0) ? -1 : 1;
      string name = OBJ_PREFIX + (side == 0 ? "FL_S_" : "FL_B_") + ts;
      double zf   = (sd > 0.0) ? ZFloat(dir, (open - sma) / sd) : 0.0;
      bool   hit  = (zf > InpFloatMarkZ);
      bool   show = InpShowFloatMark && sd > 0.0 && (hit || (always && zf > 0.0));
      if(!show) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }
      double price = (side == 0) ? (lo - off) : (hi + off);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_UPPER : ANCHOR_LOWER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         RememberBarZLabel(name, t);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, hit ? InpClrFloatMark : InpClrBarZOther);
      ObjectSetInteger(0, name, OBJPROP_TIME, t);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, ND(price));
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("F%+.2f", zf));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ราคาเปิดลอยพ้น SMA (%s): Z_float %+.2f = (Open %s − SMA ตอนเปิดแท่ง %s) ÷ SD20 %.0f จุด",
                                   TimeToString(t, TIME_DATE|TIME_MINUTES), (side == 0 ? "ฝั่ง SELL" : "ฝั่ง BUY"), zf,
                                   DoubleToString(open, _Digits), DoubleToString(sma, _Digits), PriceToPts(sd)));
   }
}
// SMA / SD20 ของแท่ง j ที่ราคา px: ราคาปิด n−1 แท่งก่อนหน้า + px (px = ราคาเปิด → ค่าตอนเปิดแท่ง)
bool SmaSdAt(const double &c[], int j, double px, double &sma, double &sd) {
   int n = InpZ_Period;
   if(j < n - 1) return false;
   double s = px - c[j - 1], ss = s * s, ref = c[j - 1];
   for(int k = j - n + 1; k <= j - 1; k++) { double d = c[k] - ref; s += d; ss += d * d; }
   double m = s / n, v = ss / n - m * m;
   if(v <= 0.0) return false;
   sma = ref + m;
   sd  = MathSqrt(v);
   return true;
}

// ประเมินแท่งที่ปิดแล้วชุดหนึ่ง (shift เริ่มที่ from_shift จำนวน bars แท่ง)
void EvaluateClosedBars(int from_shift, int bars) {
   int n   = InpZ_Period;
   int cnt = bars + n - 1;
   double c[], h[], l[], o[];
   datetime t[];
   if(CopyClose(_Symbol, InpZ_Timeframe, from_shift, cnt, c) != cnt ||
      CopyOpen (_Symbol, InpZ_Timeframe, from_shift, cnt, o) != cnt ||
      CopyHigh (_Symbol, InpZ_Timeframe, from_shift, cnt, h) != cnt ||
      CopyLow  (_Symbol, InpZ_Timeframe, from_shift, cnt, l) != cnt ||
      CopyTime (_Symbol, InpZ_Timeframe, from_shift, cnt, t) != cnt) return;

   double zr[2], zs[2];
   bool   ok[2];
   for(int j = n - 1; j < cnt; j++) {
      double sma = 0.0, sd = 0.0;
      bool   fok = SmaSdAt(c, j, o[j], sma, sd);
      if(InpShowBarZ) {
         ok[0] = ZForBarPrice(c, j, h[j], zr[0], zs[0]);
         ok[1] = ZForBarPrice(c, j, l[j], zr[1], zs[1]);
         SetBarZLabels(t[j], h[j], l[j], zr, zs, ok);
      }
      if(fok) SetBarFloatLabel(t[j], h[j], l[j], o[j], sma, sd, false);
   }
}

// ลบป้ายของแท่งที่เก่ากว่าช่วงที่แสดง
void PruneBarZLabels() {
   datetime cutoff = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(cutoff == 0) return;
   int n = ArraySize(g_zl_names), w = 0;
   for(int i = 0; i < n; i++) {
      if(g_zl_times[i] < cutoff || ObjectFind(0, g_zl_names[i]) < 0) {
         ObjectDelete(0, g_zl_names[i]);
         continue;
      }
      g_zl_names[w] = g_zl_names[i];
      g_zl_times[w] = g_zl_times[i];
      w++;
   }
   if(w != n) { ArrayResize(g_zl_names, w); ArrayResize(g_zl_times, w); }
}

// เรียกทุก 1 วินาที: ขึ้นแท่งใหม่ → ยืนยันแท่งที่ปิด (หรือคำนวณย้อนหลังทั้งชุดครั้งแรก) + อัปเดตแท่งปัจจุบัน
void UpdateBarZLabels() {
   if(!g_draw || (!InpShowBarZ && !InpShowFloatMark) || !g_z_ready) return;
   datetime t0 = CurrentZBarTime();
   if(t0 == 0) return;
   if(g_barz_bar == 0) {
      EvaluateClosedBars(1, InpBarZBars);
      g_barz_bar = t0;
   }
   else if(t0 != g_barz_bar) {
      EvaluateClosedBars(1, 1);
      PruneBarZLabels();
      g_barz_bar = t0;
   }
   double zr[2], zs[2], px[2];
   bool   ok[2];
   px[0] = g_bar0_hi;
   px[1] = g_bar0_lo;
   for(int s = 0; s < 2; s++) {
      double fit, sig, mn, ssd;
      bool   fl;
      zr[s] = 0.0; zs[s] = 0.0;
      ok[s] = (px[s] > 0.0) && ZAtPrice(g_zc, px[s], zr[s], zs[s], fit, sig, fl, mn, ssd);
   }
   if(InpShowBarZ) SetBarZLabels(t0, g_bar0_hi, g_bar0_lo, zr, zs, ok);
   SetBarFloatLabel(t0, g_bar0_hi, g_bar0_lo, g_bar0_open, g_bar0_fsma, g_bar0_fsd, InpFloatMarkLive);
}

//====================================================================
// 📍 มาร์กจุดเปิดไม้จริง + ระยะห่างถึงปลายไส้เทียน (TF ของ Z)
//====================================================================
struct EntryMark {
   ulong    deal;
   datetime t;
   double   price;
   int      dir;      // -1 SELL / 1 BUY
   bool     closed_bar;
   string   cmt;
};
EntryMark g_marks[];
datetime  g_marks_bar = 0;

int FindMark(ulong deal) {
   for(int i = ArraySize(g_marks) - 1; i >= 0; i--)
      if(g_marks[i].deal == deal) return i;
   return -1;
}

void DrawEntryMark(EntryMark &m) {
   int shift = iBarShift(_Symbol, InpZ_Timeframe, m.t, false);
   if(shift < 0) return;
   double   hi  = iHigh(_Symbol, InpZ_Timeframe, shift);
   double   lo  = iLow (_Symbol, InpZ_Timeframe, shift);
   datetime bt  = iTime(_Symbol, InpZ_Timeframe, shift);
   if(hi <= 0.0 || lo <= 0.0) return;

   bool   is_sell = (m.dir == -1);
   double tip     = is_sell ? hi : lo;
   double gap     = is_sell ? (hi - m.price) : (m.price - lo);
   if(gap < 0.0) gap = 0.0;
   double gap_pts = PriceToPts(gap);
   double range   = hi - lo;
   string ds      = IntegerToString((long)m.deal);
   int    sys     = SysFromComment(m.cmt);

   string na = OBJ_PREFIX + "EN_A_" + ds;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, m.t, m.price);
      ObjectSetInteger(0, na, OBJPROP_COLOR, is_sell ? InpClrEntrySell : InpClrEntryBuy);
      ObjectSetInteger(0, na, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }
   string ng = OBJ_PREFIX + "EN_G_" + ds;
   if(ObjectFind(0, ng) < 0) {
      ObjectCreate(0, ng, OBJ_TREND, 0, m.t, m.price, m.t, tip);
      ObjectSetInteger(0, ng, OBJPROP_COLOR, InpClrEntryGap);
      ObjectSetInteger(0, ng, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, ng, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, ng, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ng, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ng, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, ng, 1, m.t, tip);
   string nt = OBJ_PREFIX + "EN_T_" + ds;
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, m.t, m.price);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nt, OBJPROP_COLOR, InpClrEntryGap);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("   %s%s | %s | ห่างไส้ %.0f", (sys >= 0 ? SysTag(sys) + " " : ""), (is_sell ? "S" : "B"),
                                                    BarMinText(m.t), gap_pts));
   string tipText = StringFormat("%s @ %s | %s แท่ง %s = %s | ห่างปลายไส้ %.0f จุด (%.0f%% ของช่วงแท่ง)%s | %s",
                                 (is_sell ? "SELL" : "BUY"), DoubleToString(m.price, _Digits),
                                 (is_sell ? "High" : "Low"), TimeToString(bt, TIME_DATE|TIME_MINUTES),
                                 DoubleToString(tip, _Digits), gap_pts, (range > 0.0 ? 100.0 * gap / range : 0.0),
                                 (shift == 0 ? " (แท่งยังไม่ปิด)" : ""), m.cmt);
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, ng, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tipText);
   m.closed_bar = (shift > 0);
}

// เพิ่มมาร์กจาก deal เปิดไม้ของ EA (deal ต้องถูกเลือกใน history แล้ว)
void AddEntryMarkFromDeal(ulong deal) {
   if(!g_draw || !InpShowEntryMarks) return;
   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;
   long type = HistoryDealGetInteger(deal, DEAL_TYPE);
   if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) return;
   if(FindMark(deal) >= 0) return;

   int n = ArraySize(g_marks);
   ArrayResize(g_marks, n + 1);
   g_marks[n].deal  = deal;
   g_marks[n].t     = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   g_marks[n].price = HistoryDealGetDouble(deal, DEAL_PRICE);
   g_marks[n].dir   = (type == DEAL_TYPE_SELL) ? -1 : 1;
   g_marks[n].closed_bar = false;
   g_marks[n].cmt   = HistoryDealGetString(deal, DEAL_COMMENT);
   DrawEntryMark(g_marks[n]);
}
// โหลดไม้ย้อนหลังจาก Deal History เท่าช่วงป้าย Z
void LoadEntryMarksFromHistory() {
   if(!g_draw || !InpShowEntryMarks) return;
   datetime from = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(from == 0) from = ServerNow() - (datetime)(PeriodSeconds(InpZ_Timeframe) * InpBarZBars);
   if(!HistorySelect(from, ServerNow() + 60)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++) {
      ulong deal = HistoryDealGetTicket(i);
      if(deal > 0) AddEntryMarkFromDeal(deal);
   }
}
void DeleteEntryMarkObjects(ulong deal) {
   string ds = IntegerToString((long)deal);
   ObjectDelete(0, OBJ_PREFIX + "EN_A_" + ds);
   ObjectDelete(0, OBJ_PREFIX + "EN_G_" + ds);
   ObjectDelete(0, OBJ_PREFIX + "EN_T_" + ds);
}
void UpdateEntryMarks() {
   if(!g_draw || !InpShowEntryMarks) return;
   for(int i = ArraySize(g_marks) - 1; i >= 0; i--)
      if(!g_marks[i].closed_bar) DrawEntryMark(g_marks[i]);

   datetime t0 = CurrentZBarTime();
   if(t0 == 0 || t0 == g_marks_bar) return;
   g_marks_bar = t0;
   datetime cutoff = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(cutoff == 0) return;
   int n = ArraySize(g_marks), w = 0;
   for(int i = 0; i < n; i++) {
      if(g_marks[i].t < cutoff) { DeleteEntryMarkObjects(g_marks[i].deal); continue; }
      g_marks[w++] = g_marks[i];
   }
   if(w != n) ArrayResize(g_marks, w);
}

//====================================================================
// 🧪 TICK REPLAY (ข้อมูล tick จริงย้อนหลัง → ไม้จำลอง)
//====================================================================
void ReplayReset() {
   ArrayResize(g_rt, 0);
   ArrayResize(g_rb, 0);
   ArrayResize(g_sh, 0);
   ArrayResize(g_rr, 0);
   ArrayResize(g_rc, 0);
   g_rb_drawn = 0; g_sh_drawn = 0;
   g_rp.Reset();
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false; g_rp_hi = 0.0; g_rp_lo = 0.0;
   g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_msc = 0;
   g_rp_have = false; g_rp_init = false; g_rp_caught = false;
   g_rp_cursor = 0; g_rp_retry = 0; g_rp_ticks = 0; g_rp_news_wait = 0;
   g_rp_status = "ยังไม่เริ่ม";
   g_pt_from = 0;
   g_rp_csv_rows = -1;
   g_rp_csv_pt   = -1;
}

// โหลดแท่ง (TF ของ Z) ครอบช่วง Replay + ความจำ N9
bool ReplayLoadRates() {
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int count   = (InpReplayDays + InpN9_Days + 4) * per_day + InpZ_Period + 10;
   int got = CopyRates(_Symbol, InpZ_Timeframe, 0, count, g_rr);
   if(got <= InpZ_Period + 3) return false;
   ArrayResize(g_rc, got);
   for(int i = 0; i < got; i++) g_rc[i] = g_rr[i].close;
   return true;
}

// เข้าแท่งใหม่ (TF ของ Z): สร้างแคช Z + แท่งที่เพิ่งปิด → ความจำ N9
void ReplayEnterBar(int b) {
   g_rp_b = b;
   if(g_rr[b].time == g_rp_bar_t) return;
   g_rp_bar_t = g_rr[b].time;
   g_rp_zc.ok = false;
   g_rp_hi    = 0.0;
   g_rp_lo    = 0.0;
   int n = InpZ_Period;
   if(b >= n) {
      double c[];
      ArrayResize(c, n);
      for(int i = 0; i < n; i++) c[i] = g_rr[b - n + i].close;
      BuildZCache(c, g_rp_zc);
      g_rp.MemFromBar(g_rc, b - 1, g_rr[b - 1].high, g_rr[b - 1].low, g_rr[b - 1].time);
   }
   g_rp.MemPrune(g_rr[b].time - (datetime)(InpN9_Days * DAY_SEC));
}

// ความจำ N9 ก่อนเริ่มเล่นซ้ำ: แท่งปิดก่อนเวลา t
void ReplaySeedMemory(datetime t) {
   int n = InpZ_Period;
   for(int j = n - 1; j < ArraySize(g_rr); j++) {
      if(g_rr[j].time + (datetime)PeriodSeconds(InpZ_Timeframe) > t) break;
      g_rp.MemFromBar(g_rc, j, g_rr[j].high, g_rr[j].low, g_rr[j].time);
   }
   g_rp.MemPrune(t - (datetime)(InpN9_Days * DAY_SEC));
}

bool ReplayBarFor(datetime t) {
   int n = ArraySize(g_rr);
   if(n == 0) return false;
   if(t >= g_rr[n - 1].time + (datetime)PeriodSeconds(InpZ_Timeframe)) {
      if(!ReplayLoadRates()) return false;
      n = ArraySize(g_rr);
      g_rp_b = -1;
   }
   if(g_rp_b < 0 || g_rp_b >= n || g_rr[g_rp_b].time > t) {
      int b = -1;
      for(int i = n - 1; i >= 0; i--) if(g_rr[i].time <= t) { b = i; break; }
      if(b < 0) return false;
      ReplayEnterBar(b);
      return true;
   }
   int b = g_rp_b;
   while(b + 1 < n && g_rr[b + 1].time <= t) b++;
   ReplayEnterBar(b);
   return true;
}

// ติดตามต่อหลังเข้าไม้ (ไม่ขึ้นกับการปิดไม้): Z_SMA สูงสุด (ทิศของการกระชากของจุด A), ราคาสวน / ไปทางกำไรสูงสุด, เวลากลับถึง Z
void ReplayPostTrack(long msc, double bid, double zs) {
   long span = (long)InpPostTrack_Min * 60000;
   int  n    = ArraySize(g_rt);
   for(int i = g_pt_from; i < n; i++) {
      if(!g_rt[i].pt_done && msc - g_rt[i].msc_in > span) g_rt[i].pt_done = true;
      if(g_rt[i].pt_done) { if(i == g_pt_from) g_pt_from++; continue; }
      double zd  = (g_rt[i].side == 1) ? -zs : zs;
      double adv = (g_rt[i].dir == -1) ? bid - g_rt[i].p_in : g_rt[i].p_in - bid;
      if(zd > g_rt[i].pt_zs_max) g_rt[i].pt_zs_max = zd;
      if(adv > g_rt[i].pt_adv)   g_rt[i].pt_adv    = adv;
      if(-adv > g_rt[i].pt_fav)  g_rt[i].pt_fav    = -adv;
      if(g_rt[i].pt_back_sec < 0.0 && zd <= InpPostBackZ) g_rt[i].pt_back_sec = (double)(msc - g_rt[i].msc_in) / 1000.0;
   }
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);
   if(!ReplayBarFor(t)) return;
   if(g_rp_hi <= 0.0 || bid > g_rp_hi) g_rp_hi = bid;
   if(g_rp_lo <= 0.0 || bid < g_rp_lo) g_rp_lo = bid;
   int ts = GetTimeStateAt(t);
   g_rp.Step(msc, bid, ask, true, g_rp_zc, g_rp_hi, g_rp_lo, ts, EntryBlockReason(ts, bid, ask, t));
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(ZAtPrice(g_rp_zc, bid, zr, zs, fit, sig, fl, mn, ssd)) ReplayPostTrack(msc, bid, zs);
   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc;
   g_rp_have = true;
   g_rp_ticks++;
}

string ReplayReasonName(int r) {
   switch(r) {
      case RX_TP:    return "TP";
      case RX_SL:    return "SL";
      case RX_CUT:   return "ตัดเวลา";
      case RX_TRAIL: return "โล่";
      case RX_WEEK:  return "ปิดสัปดาห์";
      case RX_BE:    return "บังทุน";
   }
   return "ถืออยู่";
}

string ReplayReasonCode(int r) {
   switch(r) {
      case RX_TP:    return "TP";
      case RX_SL:    return "SL";
      case RX_CUT:   return "TIMECUT";
      case RX_TRAIL: return "TRAIL";
      case RX_WEEK:  return "WEEKCLOSE";
      case RX_BE:    return "BE";
   }
   return "OPEN";
}

// ข้อความเฉพาะระบบ (tooltip / CSV)
string SysInfoText(int i) {
   switch(g_rt[i].sys) {
      case SYS_N2: return StringFormat("ไม้เงาพลาด %d ครั้ง → ตามเทรนด์", g_rt[i].n2_miss);
      case SYS_N4: return StringFormat("tick/วิ ยอดใหม่ ÷ ยอดก่อน = %.2f", g_rt[i].info);
      case SYS_N9: return StringFormat("แตะระดับ %s (ห่าง %.0f จุด)", DoubleToString(g_rt[i].info, _Digits), PriceToPts(MathAbs(g_rt[i].p_in - g_rt[i].info)));
   }
   return "";
}

void DrawReplayTrade(int i) {
   datetime t_in    = (datetime)(g_rt[i].msc_in / 1000);
   bool     is_sell = (g_rt[i].dir == -1);
   string   id      = IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
   bool     open    = (g_rt[i].reason == RX_OPEN);
   color    clr     = g_sys_clr[g_rt[i].sys];
   string   tag     = SysTag(g_rt[i].sys);
   color    res_clr = open ? clr : ((g_rt[i].pnl > 0.0) ? InpClrSimWin : InpClrSimLoss);

   string na = OBJ_PREFIX + "RP_A_" + id, nl = OBJ_PREFIX + "RP_L_" + id;
   string np = OBJ_PREFIX + "RP_P_" + id, nt = OBJ_PREFIX + "RP_T_" + id;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, t_in, g_rt[i].p_in);
      ObjectSetInteger(0, na, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }
   if(g_rt[i].part && ObjectFind(0, np) < 0) {
      ObjectCreate(0, np, OBJ_ARROW, 0, (datetime)(g_rt[i].part_msc / 1000), g_rt[i].part_px);
      ObjectSetInteger(0, np, OBJPROP_ARROWCODE, 159);   // ● ปิดบางส่วน
      ObjectSetInteger(0, np, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, np, OBJPROP_COLOR, InpClrSimWin);
      ObjectSetInteger(0, np, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, np, OBJPROP_HIDDEN, true);
   }
   if(!open) {
      datetime t_out = (datetime)(g_rt[i].msc_out / 1000);
      if(ObjectFind(0, nl) < 0) {
         ObjectCreate(0, nl, OBJ_TREND, 0, t_in, g_rt[i].p_in, t_out, g_rt[i].p_out);
         ObjectSetInteger(0, nl, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, nl, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nl, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, nl, OBJPROP_COLOR, res_clr);
   }
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_in, g_rt[i].p_in);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, nt, OBJPROP_COLOR, res_clr);
   ObjectSetString(0, nt, OBJPROP_TEXT,
                   open ? StringFormat("%s %s %.2f | %s | ถืออยู่   ", tag, (is_sell ? "S" : "B"), g_rt[i].lot0, BarMinText(t_in))
                        : StringFormat("%s %s %.2f | %s | %s%s %+.0f ($%+.2f)   ", tag, (is_sell ? "S" : "B"), g_rt[i].lot0, BarMinText(t_in),
                                       (g_rt[i].part ? "½ + " : ""), ReplayReasonName(g_rt[i].reason), g_rt[i].pnl, g_rt[i].usd));

   string tipText = StringFormat("จำลอง %s %s %.2f lot @ %s (%s, %s ของแท่ง) | จุด A %s เริ่ม %s (เข้าหลัง %.0f วิ)",
                                 tag, (is_sell ? "SELL" : "BUY"), g_rt[i].lot0, DoubleToString(g_rt[i].p_in, _Digits),
                                 TimeToString(t_in, TIME_DATE|TIME_SECONDS), BarMinText(t_in), (g_rt[i].side == 1 ? "ขาลง" : "ขาขึ้น"),
                                 TimeToString((datetime)(g_rt[i].a_msc / 1000), TIME_MINUTES|TIME_SECONDS),
                                 (double)(g_rt[i].msc_in - g_rt[i].a_msc) / 1000.0);
   tipText += StringFormat("\nZ ตอนเข้า R %+.2f / S %+.2f (Z* %+.2f) | SL %s (R %.0f จุด)%s",
                           g_rt[i].zr, g_rt[i].zs, ZStar(g_rt[i].zs), DoubleToString(g_rt[i].sl0, _Digits),
                           PriceToPts(MathAbs(g_rt[i].p_in - g_rt[i].sl0)), (g_rt[i].tp > 0.0 ? " | TP " + DoubleToString(g_rt[i].tp, _Digits) : ""));
   string si = SysInfoText(i);
   if(si != "") tipText += "\n" + si;
   if(g_rt[i].part)
      tipText += StringFormat("\nปิดบางส่วน %.2f lot @ %s (%s)", g_rt[i].part_lot, DoubleToString(g_rt[i].part_px, _Digits),
                              TimeToString((datetime)(g_rt[i].part_msc / 1000), TIME_DATE|TIME_SECONDS));
   if(!open)
      tipText += StringFormat("\nออก %s @ %s (%s) | %+.0f จุด | $%+.2f | ถือ %d วินาที",
                              ReplayReasonName(g_rt[i].reason), DoubleToString(g_rt[i].p_out, _Digits),
                              TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS),
                              g_rt[i].pnl, g_rt[i].usd, (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000))
               + StringFormat("\nระยะกำไรระหว่างถือ: ต่ำสุด %+.0f / สูงสุด %+.0f / เฉลี่ย %+.0f จุด",
                              PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ProfitAvgPts(i));
   if(g_rt[i].pt_done)
      tipText += StringFormat("\nติดตาม %d นาทีหลังเข้า: Z_SMA สูงสุด %+.2f (Z* %+.2f) | สวนสูงสุด %.0f / ไปทางกำไรสูงสุด %.0f จุด | กลับถึง Z %.1f %s",
                              InpPostTrack_Min, g_rt[i].pt_zs_max, ZStar(g_rt[i].pt_zs_max), PriceToPts(g_rt[i].pt_adv), PriceToPts(g_rt[i].pt_fav),
                              InpPostBackZ, (g_rt[i].pt_back_sec >= 0.0 ? StringFormat("ใน %.0f วิ", g_rt[i].pt_back_sec) : "ไม่ถึง"));
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tipText);
   if(!open)        ObjectSetString(0, nl, OBJPROP_TOOLTIP, tipText);
   if(g_rt[i].part) ObjectSetString(0, np, OBJPROP_TOOLTIP, tipText);
   g_rt[i].drawn_final = (!open && g_rt[i].pt_done);
}

void DrawReplayBlocked(int k) {
   datetime t  = (datetime)(g_rb[k].msc / 1000);
   string   nx = OBJ_PREFIX + "RP_X_" + IntegerToString(g_rb[k].msc) + "_" + IntegerToString(g_rb[k].sys);
   if(ObjectFind(0, nx) < 0) {
      ObjectCreate(0, nx, OBJ_ARROW, 0, t, g_rb[k].price);
      ObjectSetInteger(0, nx, OBJPROP_ARROWCODE, 251);   // ×
      ObjectSetInteger(0, nx, OBJPROP_COLOR, InpClrSimBlocked);
      ObjectSetInteger(0, nx, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, nx, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nx, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nx, OBJPROP_TOOLTIP,
                   StringFormat("สัญญาณ %s %s ถูกทิ้ง %s @ %s\nเหตุผล: %s", SysTag(g_rb[k].sys), (g_rb[k].dir == -1 ? "SELL" : "BUY"),
                                TimeToString(t, TIME_DATE|TIME_SECONDS), DoubleToString(g_rb[k].price, _Digits), g_rb[k].why));
}

// ไม้เงาของ N2: ○ เปิด / ✕ พลาด (โดน SL) / ✓ ได้ 1R
void DrawReplayShadow(int k) {
   datetime t  = (datetime)(g_sh[k].msc / 1000);
   string   nm = OBJ_PREFIX + "RP_H_" + IntegerToString(g_sh[k].msc) + "_" + IntegerToString(k);
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_ARROW, 0, t, g_sh[k].price);
      ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, g_sh[k].kind == 0 ? 161 : (g_sh[k].kind == 1 ? 251 : 252));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, InpClrShadow);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   string what = (g_sh[k].kind == 0) ? StringFormat("เปิดไม้เงาสวน (พลาดมาแล้ว %d/%d)", g_sh[k].miss, InpN2_Misses)
               : (g_sh[k].kind == 1) ? StringFormat("ไม้เงาโดน SL → พลาด %d/%d", g_sh[k].miss, InpN2_Misses)
               : "ไม้เงาได้ 1R → นับพลาดใหม่";
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, StringFormat("N2 เงา (จุด A %s) %s @ %s\n%s", (g_sh[k].side == 1 ? "ขาลง" : "ขาขึ้น"),
                                                        TimeToString(t, TIME_DATE|TIME_SECONDS), DoubleToString(g_sh[k].price, _Digits), what));
}

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rt); i++)
      if(!g_rt[i].drawn_final) DrawReplayTrade(i);
   if(InpShowReplayBlocked)
      for(; g_rb_drawn < ArraySize(g_rb); g_rb_drawn++) DrawReplayBlocked(g_rb_drawn);
   for(; g_sh_drawn < ArraySize(g_sh); g_sh_drawn++) DrawReplayShadow(g_sh_drawn);
}

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n = 0, w = 0;
   int    cnt[NSYS];
   int    win[NSYS];
   int    prt[NSYS];
   double usd = 0.0, peak = 0.0, dd = 0.0;
   double usd_s[NSYS];
   ArrayInitialize(cnt, 0); ArrayInitialize(win, 0); ArrayInitialize(prt, 0); ArrayInitialize(usd_s, 0.0);
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      int s = g_rt[i].sys;
      n++; cnt[s]++;
      if(g_rt[i].usd > 0.0) { w++; win[s]++; }
      if(g_rt[i].part) prt[s]++;
      usd += g_rt[i].usd;
      usd_s[s] += g_rt[i].usd;
      if(usd > peak) peak = usd;
      if(usd - peak < dd) dd = usd - peak;
   }
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | ถูกทิ้ง %d",
                           InpReplayDays, g_rp_status, n, (n > 0 ? 100.0 * w / n : 0.0), usd, dd, ArraySize(g_rb));
   string line = "";
   for(int k = 0; k < NSYS; k++) {
      if(cnt[k] == 0) { line += StringFormat("%s -  ", SysTag(k)); continue; }
      line += StringFormat("%s %d ไม้ ชนะ %.0f%% $%+.2f%s  ", SysTag(k), cnt[k], 100.0 * win[k] / cnt[k], usd_s[k],
                           (k == SYS_T4 ? "" : StringFormat(" (½ %d)", prt[k])));
   }
   s += "\n   " + line;
   if(g_rp.CountOpen() > 0) s += StringFormat("| ถืออยู่ %d", g_rp.CountOpen());
   if(InpReplayCSV && g_rp_csv_rows >= 0)
      s += StringFormat("\n   📄 CSV: MQL5\\Files\\%s (%d ไม้)", ReplayCSVName(), g_rp_csv_rows);
   return s;
}

string ReplayCSVName() { return "7LCEA_Replay_" + _Symbol + ".csv"; }

string CsvNum(bool ok, double v, int digits) { return ok ? DoubleToString(v, digits) : ""; }

// เขียนไม้จำลองที่ปิดแล้ว (เขียนใหม่ทั้งไฟล์เมื่อมีไม้ปิด / ติดตามครบเพิ่ม)
void ReplayWriteCSV(int done, int pt_done) {
   string fn = ReplayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "time_in,system,side,event_side,lot,price_in,sl_init_pts,tp_pts,z_reg,z_sma,z_star,a_start,a_age_sec,a_peak_dist_pts," +
                      "n2_misses,n4_tick_ratio,n9_level,n9_dist_pts,partial,partial_time,partial_pts," +
                      "time_out,exit,hold_sec,pnl_pts,usd,profit_min_pts,profit_max_pts,profit_avg_pts," +
                      "post_min,post_max_zsma,post_max_zsma_star,post_max_adv_pts,post_max_fav_pts,post_back_z_sec\r\n");
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      double zd = (g_rt[i].side == 1) ? -g_rt[i].zs : g_rt[i].zs;
      string ln = StringFormat("%s,%s,%s,%s,%.2f,%s,%.0f,%s,%.3f,%.3f,%.3f,%s,%.1f,%.0f,",
                               TimeToString((datetime)(g_rt[i].msc_in / 1000), TIME_DATE|TIME_SECONDS), SysTag(g_rt[i].sys),
                               (g_rt[i].dir == -1 ? "SELL" : "BUY"), (g_rt[i].side == 1 ? "DOWN" : "UP"), g_rt[i].lot0,
                               DoubleToString(g_rt[i].p_in, _Digits), PriceToPts(MathAbs(g_rt[i].p_in - g_rt[i].sl0)),
                               CsvNum(g_rt[i].tp > 0.0, PriceToPts(MathAbs(g_rt[i].tp - g_rt[i].p_in)), 0),
                               g_rt[i].zr, g_rt[i].zs, ZStar(zd),
                               TimeToString((datetime)(g_rt[i].a_msc / 1000), TIME_DATE|TIME_SECONDS),
                               (double)(g_rt[i].msc_in - g_rt[i].a_msc) / 1000.0, PriceToPts(MathAbs(g_rt[i].a_peak - g_rt[i].p_in)));
      bool n2 = g_rt[i].sys == SYS_N2, n4 = g_rt[i].sys == SYS_N4, n9 = g_rt[i].sys == SYS_N9, pr = g_rt[i].part;
      double pdiff = (g_rt[i].dir == -1) ? g_rt[i].p_in - g_rt[i].part_px : g_rt[i].part_px - g_rt[i].p_in;
      ln += (n2 ? IntegerToString(g_rt[i].n2_miss) : "") + "," + CsvNum(n4, g_rt[i].info, 3) + "," +
            (n9 ? DoubleToString(g_rt[i].info, _Digits) : "") + "," + CsvNum(n9, PriceToPts(MathAbs(g_rt[i].p_in - g_rt[i].info)), 0) + "," +
            (pr ? "1" : "0") + "," + (pr ? TimeToString((datetime)(g_rt[i].part_msc / 1000), TIME_DATE|TIME_SECONDS) : "") + "," +
            CsvNum(pr, PriceToPts(pdiff), 0) + ",";
      ln += StringFormat("%s,%s,%d,%.0f,%.2f,%.0f,%.0f,%.0f,",
                         TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS), ReplayReasonCode(g_rt[i].reason),
                         (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000), g_rt[i].pnl, g_rt[i].usd,
                         PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ProfitAvgPts(i));
      bool pd = g_rt[i].pt_done;   // ยังติดตามไม่ครบ = ว่าง
      ln += (pd ? IntegerToString(InpPostTrack_Min) : "") + "," + CsvNum(pd, g_rt[i].pt_zs_max, 3) + "," + CsvNum(pd, ZStar(g_rt[i].pt_zs_max), 3) + "," +
            CsvNum(pd, PriceToPts(g_rt[i].pt_adv), 0) + "," + CsvNum(pd, PriceToPts(g_rt[i].pt_fav), 0) + "," +
            CsvNum(pd && g_rt[i].pt_back_sec >= 0.0, g_rt[i].pt_back_sec, 1) + "\r\n";
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_rp_csv_rows < 0) PrintFormat("📄 บันทึกไม้จำลอง %d ไม้ ลง MQL5\\Files\\%s (อัปเดตเมื่อมีไม้ปิดเพิ่ม)", done, fn);
   g_rp_csv_rows = done;
   g_rp_csv_pt   = pt_done;
}

// เรียกทุก 1 วินาที: ไล่เล่นซ้ำทีละช่วง (ครั้งแรกทีละ 12 ชม.) จนถึงปัจจุบัน แล้วต่อแบบสด
void ReplayStep() {
   if(!g_draw || !InpShowReplay) return;
   if(!g_rp_init) {
      if(NewsFilterOn() && !g_news_ok && g_rp_news_wait < 60) {   // ให้ตัวกรองข่าวมีผลตั้งแต่วันแรกของการเล่นซ้ำ
         g_rp_news_wait++;
         g_rp_status = "⏳ รอโหลดปฏิทินข่าว";
         return;
      }
      if(!ReplayLoadRates()) { g_rp_status = "⏳ รอประวัติแท่ง"; return; }
      g_contract  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(g_contract <= 0.0) g_contract = 100.0;
      g_rp_cursor = ((long)TimeCurrent() - (long)InpReplayDays * DAY_SEC) * 1000;
      ReplaySeedMemory((datetime)(g_rp_cursor / 1000));
      g_rp_init   = true;
   }
   long now_msc = (long)TimeCurrent() * 1000 + 999;
   if(g_last_tick_msc > now_msc) now_msc = g_last_tick_msc;

   long chunk = g_rp_caught ? (now_msc - g_rp_cursor) : (long)DAY_SEC * 500;   // 12 ชม.
   long to    = MathMin(g_rp_cursor + chunk, now_msc);
   if(to >= g_rp_cursor) {
      MqlTick ticks[];
      int got = CopyTicksRange(_Symbol, ticks, COPY_TICKS_INFO, (ulong)g_rp_cursor, (ulong)to);
      if(got < 0) { g_rp_status = StringFormat("⏳ กำลังโหลด tick (error %d)", GetLastError()); return; }
      if(got == 0 && !g_rp_caught && g_rp_retry < 3 &&
         GetTimeStateAt((datetime)((g_rp_cursor + to) / 2000)) != TS_CLOSED) {
         g_rp_retry++;   // ตลาดน่าจะเปิดแต่ยังไม่ได้ tick → รอโหลดอีกนิด
         return;
      }
      g_rp_retry = 0;
      for(int k = 0; k < got; k++) {
         if((long)ticks[k].time_msc < g_rp_cursor) continue;
         ReplayTick(ticks[k]);
      }
      if(got > 0)            g_rp_cursor = (long)ticks[got - 1].time_msc + 1;
      else if(!g_rp_caught)  g_rp_cursor = to + 1;
   }
   if(!g_rp_caught && to >= now_msc - 2000) g_rp_caught = true;
   if(g_rp_caught && g_rp_have) {   // เวลาผ่านไปโดยไม่มี tick (ตัดเวลา / จุด A หมดอายุ)
      datetime t  = (datetime)(now_msc / 1000);
      int      ts = GetTimeStateAt(t);
      g_rp.Step(now_msc, g_rp_bid, g_rp_ask, false, g_rp_zc, g_rp_hi, g_rp_lo, ts, EntryBlockReason(ts, g_rp_bid, g_rp_ask, t));
   }

   g_rp_status = g_rp_caught
                 ? StringFormat("✅ ครบแล้ว + เดินต่อแบบสด (%I64d ticks)", g_rp_ticks)
                 : StringFormat("⏳ กำลังเล่นซ้ำ ถึง %s (%I64d ticks)", TimeToString((datetime)(g_rp_cursor / 1000), TIME_DATE|TIME_MINUTES), g_rp_ticks);
   ReplayDraw();
   if(InpReplayCSV && g_rp_caught) {
      int done = 0, pt = 0;
      for(int i = 0; i < ArraySize(g_rt); i++) {
         if(g_rt[i].reason == RX_OPEN) continue;
         done++;
         if(g_rt[i].pt_done) pt++;
      }
      if(done != g_rp_csv_rows || pt != g_rp_csv_pt) ReplayWriteCSV(done, pt);
   }
}

//====================================================================
// 📰 ข่าวบนกราฟ: เส้นเวลาข่าว + แถบแท่งข่าว
//====================================================================
datetime g_newsviz_loaded = 0;
string   g_newsviz_names[];

void DrawNewsEvent(datetime t, string title, string detail) {
   string ts = IntegerToString((long)t);
   string nv = OBJ_PREFIX + "NEWS_V_" + ts;
   string nz = OBJ_PREFIX + "NEWS_Z_" + ts;

   if(ObjectFind(0, nv) < 0) {
      ObjectCreate(0, nv, OBJ_VLINE, 0, t, 0);
      ObjectSetInteger(0, nv, OBJPROP_COLOR, InpClrNewsLine);
      ObjectSetInteger(0, nv, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nv, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nv, OBJPROP_BACK, true);
      ObjectSetInteger(0, nv, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nv, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  nv, OBJPROP_TOOLTIP, detail);
      ObjectSetString(0,  nv, OBJPROP_TEXT, title);
      int n = ArraySize(g_newsviz_names);
      ArrayResize(g_newsviz_names, n + 2);
      g_newsviz_names[n] = nv; g_newsviz_names[n + 1] = nz;
   }
   else {
      string old = ObjectGetString(0, nv, OBJPROP_TOOLTIP);
      if(StringFind(old, detail) < 0) ObjectSetString(0, nv, OBJPROP_TOOLTIP, old + "\n" + detail);
   }

   if(ObjectFind(0, nz) < 0) {
      double   top = SymbolInfoDouble(_Symbol, SYMBOL_BID) * 10.0;
      long     per = MathMax(60, PeriodSeconds(InpZ_Timeframe));
      datetime b0  = t - (datetime)((long)t % per);   // แท่งข่าว (TF ของ Z)
      ObjectCreate(0, nz, OBJ_RECTANGLE, 0, b0, 0.0, b0 + (datetime)per, top);
      ObjectSetInteger(0, nz, OBJPROP_COLOR, InpClrNewsZone);
      ObjectSetInteger(0, nz, OBJPROP_FILL, true);
      ObjectSetInteger(0, nz, OBJPROP_BACK, true);
      ObjectSetInteger(0, nz, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nz, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nz, OBJPROP_TOOLTIP, ObjectGetString(0, nv, OBJPROP_TOOLTIP));
}
void LoadNewsHistory() {
   if(!g_draw || !InpShowNewsHistory || MQLInfoInteger(MQL_TESTER)) return;
   datetime now = ServerNow();
   if(g_newsviz_loaded != 0 && now - g_newsviz_loaded < 3600) return;
   g_newsviz_loaded = now;

   datetime from = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(from == 0) from = now - (datetime)(PeriodSeconds(InpZ_Timeframe) * InpBarZBars);
   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, from, now + (datetime)DAY_SEC, NULL, InpNewsCurrency)) {
      PrintFormat("⚠️ โหลดปฏิทินข่าวย้อนหลังไม่สำเร็จ (error %d)", GetLastError());
      return;
   }
   for(int i = 0; i < ArraySize(vals); i++) {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      bool high = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
      bool med  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
      if(!high && !(InpNewsIncludeMedium && med)) continue;
      string detail = StringFormat("📰 %s %s [%s] %s", TimeToString(vals[i].time, TIME_DATE|TIME_MINUTES),
                                   InpNewsCurrency, (high ? "High" : "Medium"), ev.name);
      DrawNewsEvent(vals[i].time, ev.name, detail);
   }

   // ลบข่าวที่เก่ากว่าช่วงที่แสดง
   int n = ArraySize(g_newsviz_names), w = 0;
   for(int i = 0; i + 1 < n; i += 2) {
      datetime tt = (datetime)ObjectGetInteger(0, g_newsviz_names[i], OBJPROP_TIME);
      if(tt != 0 && tt < from) {
         ObjectDelete(0, g_newsviz_names[i]);
         ObjectDelete(0, g_newsviz_names[i + 1]);
         continue;
      }
      g_newsviz_names[w++] = g_newsviz_names[i];
      g_newsviz_names[w++] = g_newsviz_names[i + 1];
   }
   if(w != n) ArrayResize(g_newsviz_names, w);
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

// สีป้าย Z ตามโซน: ถึงจุด A = แดงส้ม/ฟ้า, ใกล้จุด A = ทอง, ปกติ = เงิน
color LiveZColor(double z) {
   if(z > InpA_Z)                    return InpClrLiveSell;
   if(z < -InpA_Z)                   return InpClrLiveBuy;
   if(MathAbs(z) >= InpA_Z - NEAR_ZONE) return InpClrLiveNear;
   return InpClrLiveNormal;
}

// ป้ายค่า Z สด: ติดขอบขวาของกราฟ ที่ความสูงเดียวกับราคา Bid
void UpdateLiveZLabel(double bid) {
   if(!g_draw || !InpShowLiveZ) return;
   if(!g_z_valid) {
      if(ObjectFind(0, LABEL_LIVE_Z) >= 0) ObjectDelete(0, LABEL_LIVE_Z);
      g_live_z_text = "";
      return;
   }
   string text = StringFormat("R %+.2f | S %+.2f ▶", g_z_reg, g_z_sma);
   if(g_lv.m_ev[0].active)      text = "จุด A ขึ้น  |  " + text;
   else if(g_lv.m_ev[1].active) text = "จุด A ลง  |  " + text;

   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, 0), bid, x, y)) return;
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(y < 8)     y = 8;
   if(y > h - 8) y = h - 8;
   if(text == g_live_z_text && y == g_live_z_y && ObjectFind(0, LABEL_LIVE_Z) >= 0) return;

   if(ObjectFind(0, LABEL_LIVE_Z) < 0) {
      ObjectCreate(0, LABEL_LIVE_Z, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetString(0,  LABEL_LIVE_Z, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_FONTSIZE, InpLiveZFontSize);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_XDISTANCE, MathMax(0, InpLiveZOffsetPx));
   ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  LABEL_LIVE_Z, OBJPROP_TEXT, text);
   ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_COLOR, LiveZColor(g_z));
   ObjectSetString(0,  LABEL_LIVE_Z, OBJPROP_TOOLTIP,
                   StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s, Z* %+.2f) | จุด A ตัวใด > %.2f / T4 > %.2f",
                                g_z_reg, DoubleToString(g_center, _Digits), g_z_sma, DoubleToString(g_sma_mean, _Digits), ZStar(g_z_sma),
                                InpA_Z, InpT4_Z));
   g_live_z_text = text;
   g_live_z_y    = y;
}

void UpdateZLines() {
   if(!g_draw || !g_z_valid) return;
   if(InpShowZLines) {
      MoveHLine(LINE_MAIN, g_center,                   InpClrZCenter,   STYLE_DOT,  1, "[Regression] เส้นกลาง Z = 0", g_line_main);
      MoveHLine(LINE_SELL, g_center + InpA_Z * g_sigma, InpClrZSellLine, STYLE_DASH, 1, StringFormat("[Regression] จุด A ขาขึ้น Z > +%.2f", InpA_Z), g_line_sell);
      MoveHLine(LINE_BUY,  g_center - InpA_Z * g_sigma, InpClrZBuyLine,  STYLE_DASH, 1, StringFormat("[Regression] จุด A ขาลง Z < −%.2f", InpA_Z),  g_line_buy);
   }
   if(InpShowSmaZLines) {
      MoveHLine(LINE_SMA_MAIN, g_sma_mean,                    InpClrSmaCenter,   STYLE_DOT,     1, "[SMA20] เส้นกลาง Z = 0", g_line_sma_main);
      MoveHLine(LINE_SMA_SELL, g_sma_mean + InpA_Z * g_sma_sd, InpClrSmaSellLine, STYLE_DASHDOT, 1, StringFormat("[SMA20] จุด A ขาขึ้น Z > +%.2f", InpA_Z), g_line_sma_sell);
      MoveHLine(LINE_SMA_BUY,  g_sma_mean - InpA_Z * g_sma_sd, InpClrSmaBuyLine,  STYLE_DASHDOT, 1, StringFormat("[SMA20] จุด A ขาลง Z < −%.2f", InpA_Z),  g_line_sma_buy);
   }
}

// สถานะจุด A ฝั่ง k ของ EA จริง (Dashboard)
string EventText(int k, long now_msc) {
   string side = (k == 0) ? "ขาขึ้น" : "ขาลง ";
   if(!g_lv.m_ev[k].active) return "จุด A " + side + ": -";
   string s = StringFormat("จุด A %s: เริ่ม %s (%s) | ยอด %s", side,
                           TimeToString((datetime)(g_lv.m_ev[k].start_msc / 1000), TIME_MINUTES|TIME_SECONDS),
                           FormatDuration((now_msc - g_lv.m_ev[k].start_msc) / 1000), DoubleToString(g_lv.m_ev[k].peak, _Digits));
   if(g_lv.m_ev[k].e1_on) s += StringFormat(" | E1 Buy ≥ %s / Sell ≤ %s", DoubleToString(g_lv.m_ev[k].e1_up, _Digits), DoubleToString(g_lv.m_ev[k].e1_dn, _Digits));
   if(g_lv.m_ev[k].n1_on) s += StringFormat(" | N1 %s ที่ %s", (k == 0 ? "Sell" : "Buy"), DoubleToString(g_lv.m_ev[k].n1_px, _Digits));
   if(g_en[SYS_N2] && !g_lv.m_ev[k].done[SYS_N2])
      s += StringFormat(" | N2 เงาพลาด %d/%d%s", g_lv.m_ev[k].misses, InpN2_Misses,
                        (g_lv.m_ev[k].sh_open ? " (เงา @ " + DoubleToString(g_lv.m_ev[k].sh_px, _Digits) + ")" : ""));
   string used = "";
   for(int i = 0; i < NSYS; i++) if(g_lv.m_ev[k].done[i]) used += SysTag(i) + " ";
   if(used != "") s += " | ใช้สิทธิ์แล้ว: " + used;
   return s;
}

string PositionLines(double bid, double ask) {
   string out = "";
   for(int i = 0; i < ArraySize(g_lv.m_pos); i++) {
      if(!g_lv.m_pos[i].open) continue;
      int    d    = g_lv.m_pos[i].dir;
      double prof = (d == -1) ? PriceToPts(g_lv.m_pos[i].p_in - ask) : PriceToPts(bid - g_lv.m_pos[i].p_in);
      double R    = PriceToPts(MathAbs(g_lv.m_pos[i].p_in - g_lv.m_pos[i].sl0));
      string st   = (g_lv.m_pos[i].sys == SYS_T4)
                    ? (g_lv.m_pos[i].activated ? "🔥 ไล่จี้" : StringFormat("รอกำไรถึง %.0f", InpTrailStart_Pts))
                    : (g_lv.m_pos[i].partial ? "½ ปิดแล้ว + Chandelier" : StringFormat("รอ %.1fR (%.0f จุด)", InpPartial_R, InpPartial_R * R));
      out += StringFormat("\n  #%I64u %s %s %.2f @ %s | กำไร %+.0f จุด | SL %s | %s",
                          g_lv.m_pos[i].ticket, SysTag(g_lv.m_pos[i].sys), (d == 1 ? "BUY" : "SELL"), g_lv.m_pos[i].lot,
                          DoubleToString(g_lv.m_pos[i].p_in, _Digits), prof, DoubleToString(g_lv.m_pos[i].sl, _Digits), st);
   }
   return out;
}

void UpdateDashboard(int ts, datetime now) {
   if(!g_draw || !InpShowDashboard) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int buys, sells;
   CountPositions(buys, sells);
   string z_str = g_z_valid
      ? StringFormat("Z_reg %+.2f (กลาง %s, σ %.0f จุด%s)  |  Z_SMA %+.2f (SMA20 %s, σ %.0f จุด) | Z* %+.2f (ไม่มีเพดาน)",
                     g_z_reg, DoubleToString(g_center, _Digits), PriceToPts(g_sigma), (g_sigma_floor ? " พื้น" : ""),
                     g_z_sma, DoubleToString(g_sma_mean, _Digits), PriceToPts(g_sma_sd), ZStar(g_z_sma))
      : "รอข้อมูลแท่งเทียน...";
   string news_str = NextNewsText(now);
   long   now_msc  = MathMax(g_last_tick_msc, (long)now * 1000);
   string sys = "";
   for(int i = 0; i < NSYS; i++) sys += StringFormat("%s %s  ", SysTag(i), (g_en[i] ? "✅" : "⛔"));
   string msg = StringFormat("=== 📊 7-Lines Point-A EA v13.00 | จุด A: Z ตัวใด > %.1f | %s===\n", InpA_Z, sys);
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : R %+.2f / S %+.2f%s\n", g_prev_close_zr, g_prev_close_zs, (news_str == "" ? "" : " | " + news_str));
   msg += EventText(0, now_msc) + "\n";
   msg += EventText(1, now_msc) + "\n";
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด | จัดการไม้: %.1fR ปิด %.0f%% + บังทุน → Chandelier %.1fσ | ตัดเวลา %d นาที\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts, InpPartial_R, InpPartial_Pct, InpChand_Sigma, InpTimeCut_Min);
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
   msg += "สถานะล่าสุด : " + g_last_status;
   if(InpShowReplay) msg += "\n" + ReplayStatsText();
   msg += PositionLines(bid, ask);
   if(msg != g_last_comment) {
      g_last_comment = msg;
      Comment(msg);
   }
}

//====================================================================
// 🔘 ปุ่มเปิด/ปิดระบบ + ป้ายไม้ไม่ซ้อนกัน
//====================================================================
// เวลาภายในแท่ง (TF ของ Z) เช่น "น.07:32" = นาทีที่ 7 วินาทีที่ 32 นับจากเปิดแท่ง
string BarMinText(datetime t) {
   long sec = (long)t - (long)BarStartOf(t);
   return StringFormat("น.%02d:%02d", (int)(sec / 60), (int)(sec % 60));
}

string SysGVName(int s) { return StringFormat("7LCEA_%s_%I64d_%s", _Symbol, InpMagic, SysTag(s)); }

// ค่าเริ่มต้นของปุ่ม: แก้ input = ใช้ input / เปลี่ยน TF, คอมไพล์ใหม่, สลับบัญชี = ใช้สถานะปุ่มล่าสุด
void SysEnableInit() {
   int  r       = UninitializeReason();
   bool restore = (r == REASON_CHARTCHANGE || r == REASON_RECOMPILE || r == REASON_ACCOUNT);
   g_en[SYS_T4] = InpEnT4; g_en[SYS_E1] = InpEnE1; g_en[SYS_N1] = InpEnN1;
   g_en[SYS_N2] = InpEnN2; g_en[SYS_N4] = InpEnN4; g_en[SYS_N9] = InpEnN9;
   for(int s = 0; s < NSYS; s++) {
      if(restore && GlobalVariableCheck(SysGVName(s))) g_en[s] = (GlobalVariableGet(SysGVName(s)) > 0.5);
      GlobalVariableSet(SysGVName(s), g_en[s] ? 1.0 : 0.0);
   }
}

void DrawSysButtons() {
   if(!g_draw) return;
   for(int s = 0; s < NSYS; s++) {
      string nm = BTN_PREFIX + IntegerToString(s);
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10 + s * 64);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 34);
         ObjectSetInteger(0, nm, OBJPROP_XSIZE, 60);
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
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP, StringFormat("คลิกเพื่อ%s %s (Tick Replay จะเล่นซ้ำใหม่ตามระบบที่เปิด)", (g_en[s] ? "ปิด" : "เปิด"), SysTag(s)));
   }
}

// สลับระบบ → เก็บสถานะ, ล้างคำสั่งรอของระบบนั้น, เล่นซ้ำ Tick Replay ใหม่
void ToggleSys(int s) {
   if(s < 0 || s >= NSYS) return;
   g_en[s] = !g_en[s];
   GlobalVariableSet(SysGVName(s), g_en[s] ? 1.0 : 0.0);
   for(int k = 0; k < 2; k++) {
      if(s == SYS_E1) g_lv.m_ev[k].e1_on = false;
      if(s == SYS_N1) g_lv.m_ev[k].n1_on = false;
      if(s == SYS_N2) { g_lv.m_ev[k].sh_open = false; g_lv.m_ev[k].misses = 0; }
   }
   ObjectsDeleteAll(0, OBJ_PREFIX + "RP_");
   ReplayReset();
   g_lay_sig     = "";
   g_last_status = StringFormat("%s %s (ปุ่ม) — Tick Replay เริ่มเล่นซ้ำใหม่", SysTag(s), (g_en[s] ? "เปิด" : "ปิด"));
   PrintFormat("🔘 %s", g_last_status);
   DrawSysButtons();
}

// จัดป้ายไม้ (Tick Replay + ไม้จริง) ที่มองเห็นไม่ให้ซ้อนกัน: เรียงตามเวลา, ป้ายที่ทับป้ายก่อนหน้าถูกเลื่อนขึ้น/ลงทีละแถว
//   + เส้นโยงจากจุดเข้าไม้ถึงป้ายที่ถูกเลื่อน — จัดใหม่เมื่อซูม / เลื่อน / สเกลราคา / มีไม้ใหม่
void LayoutTradeLabels() {
   if(!g_draw) return;
   long   first = ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   long   wb    = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   long   hpx   = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   long   wpx   = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   double pmax  = ChartGetDouble(0, CHART_PRICE_MAX);
   double pmin  = ChartGetDouble(0, CHART_PRICE_MIN);
   string sig   = StringFormat("%I64d|%I64d|%I64d|%I64d|%.5f|%.5f|%d|%d", first, wb, hpx, wpx, pmax, pmin, ArraySize(g_rt), ArraySize(g_marks));
   if(sig == g_lay_sig) return;
   g_lay_sig = sig;
   if(hpx <= 0 || pmax <= pmin) return;
   datetime t_from = iTime(_Symbol, PERIOD_CURRENT, (int)first);
   if(t_from == 0) return;
   t_from -= (datetime)(PeriodSeconds(PERIOD_CURRENT) * 60);   // ป้ายทางซ้ายที่ข้อความยาวเข้ามาในจอ
   double ppx = (pmax - pmin) / (double)hpx;

   string   nm[];
   datetime tt[];
   double   pp[];
   bool     rt[];   // true = ข้อความอยู่ซ้ายของจุด (ANCHOR_RIGHT)
   color    cc[];
   int      n = 0;
   for(int i = 0; i < ArraySize(g_rt); i++) {
      datetime t = (datetime)(g_rt[i].msc_in / 1000);
      if(t < t_from) continue;
      string name = OBJ_PREFIX + "RP_T_" + IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
      if(ObjectFind(0, name) < 0) continue;
      ArrayResize(nm, n + 1); ArrayResize(tt, n + 1); ArrayResize(pp, n + 1); ArrayResize(rt, n + 1); ArrayResize(cc, n + 1);
      nm[n] = name; tt[n] = t; pp[n] = g_rt[i].p_in; rt[n] = true; cc[n] = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
      n++;
   }
   for(int k = 0; k < ArraySize(g_marks); k++) {
      if(g_marks[k].t < t_from) continue;
      string name = OBJ_PREFIX + "EN_T_" + IntegerToString((long)g_marks[k].deal);
      if(ObjectFind(0, name) < 0) continue;
      ArrayResize(nm, n + 1); ArrayResize(tt, n + 1); ArrayResize(pp, n + 1); ArrayResize(rt, n + 1); ArrayResize(cc, n + 1);
      nm[n] = name; tt[n] = g_marks[k].t; pp[n] = g_marks[k].price; rt[n] = false; cc[n] = InpClrEntryGap;
      n++;
   }
   for(int a = 1; a < n; a++) {   // เรียงตามเวลา
      int b = a;
      while(b > 0 && tt[b - 1] > tt[b]) {
         string s0 = nm[b]; nm[b] = nm[b - 1]; nm[b - 1] = s0;
         datetime t0 = tt[b]; tt[b] = tt[b - 1]; tt[b - 1] = t0;
         double p0 = pp[b]; pp[b] = pp[b - 1]; pp[b - 1] = p0;
         bool r0 = rt[b]; rt[b] = rt[b - 1]; rt[b - 1] = r0;
         color c0 = cc[b]; cc[b] = cc[b - 1]; cc[b - 1] = c0;
         b--;
      }
   }
   double x0s[], x1s[], y0s[], y1s[];
   int    placed = 0;
   for(int k = 0; k < n; k++) {
      int x = 0, y = 0;
      if(!ChartTimePriceToXY(0, 0, tt[k], pp[k], x, y)) continue;
      uint tw = 0, th = 0;
      TextSetFont(ObjectGetString(0, nm[k], OBJPROP_FONT), -10 * (int)ObjectGetInteger(0, nm[k], OBJPROP_FONTSIZE));
      TextGetSize(ObjectGetString(0, nm[k], OBJPROP_TEXT), tw, th);
      double w   = (double)tw + 4.0, h = (double)th + 2.0;
      double xa  = rt[k] ? x - w : x, xb = rt[k] ? x : x + w;
      int    off = 0;
      for(int tryi = 0; tryi <= 16; tryi++) {
         int    o   = (tryi == 0) ? 0 : ((tryi % 2 == 1) ? (tryi + 1) / 2 : -(tryi / 2));
         double ya  = y + o * h - h / 2.0, yb = ya + h;
         bool   hit = false;
         for(int q = 0; q < placed && !hit; q++)
            hit = (xa < x1s[q] && xb > x0s[q] && ya < y1s[q] && yb > y0s[q]);
         if(!hit) { off = o; break; }
      }
      double yy = y + off * h;
      double np = pp[k] - (yy - y) * ppx;
      if(MathAbs(ObjectGetDouble(0, nm[k], OBJPROP_PRICE) - np) > _Point) ObjectSetDouble(0, nm[k], OBJPROP_PRICE, np);
      string kn = nm[k] + "_K";
      if(off != 0) {
         if(ObjectFind(0, kn) < 0) {
            ObjectCreate(0, kn, OBJ_TREND, 0, tt[k], pp[k], tt[k], np);
            ObjectSetInteger(0, kn, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, kn, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, kn, OBJPROP_RAY_LEFT, false);
            ObjectSetInteger(0, kn, OBJPROP_BACK, true);
            ObjectSetInteger(0, kn, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, kn, OBJPROP_HIDDEN, true);
         }
         ObjectSetInteger(0, kn, OBJPROP_COLOR, cc[k]);
         ObjectMove(0, kn, 0, tt[k], pp[k]);
         ObjectMove(0, kn, 1, tt[k], np);
      }
      else if(ObjectFind(0, kn) >= 0) ObjectDelete(0, kn);
      ArrayResize(x0s, placed + 1); ArrayResize(x1s, placed + 1); ArrayResize(y0s, placed + 1); ArrayResize(y1s, placed + 1);
      x0s[placed] = xa; x1s[placed] = xb; y0s[placed] = yy - h / 2.0; y1s[placed] = yy + h / 2.0;
      placed++;
   }
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
int OnInit() {
   if(InpZ_Period < 2) { Print("❌ Period ต้องอย่างน้อย 2"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpBarZBars < 1 || InpBarZBars > 20000) { Print("❌ InpBarZBars ต้องอยู่ระหว่าง 1-20000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpReplayDays < 1 || InpReplayDays > 60) { Print("❌ InpReplayDays ต้องอยู่ระหว่าง 1-60"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpA_Z <= 0.0 || InpA_EndZ < 0.0 || InpA_EndZ >= InpA_Z || InpA_MaxIdle_Min < 1 || InpT4_Z <= InpA_Z) {
      Print("❌ ค่าจุด A ไม่ถูกต้อง (0 ≤ จบ < จุด A < T4, หมดอายุ ≥ 1 นาที)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpT4_Lot <= 0.0 || InpSysLot <= 0.0 || InpTP_Pts <= 0.0 || InpSLPeak_Pts < 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ Lot / TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpE1_BoxMin < 1 || InpE1_Buffer_Pts < 0.0 || InpN1_K <= 0.0 || InpN2_Z <= 0.0 || InpN2_Misses < 1 || InpN2_SL_Sigma <= 0.0 ||
      InpN4_Ratio <= 0.0 || InpN4_NewHigh_Pts < 0.0 || InpN4_Rate_Sec < 1 || InpN9_Days < 1 || InpN9_Near_Sigma <= 0.0) {
      Print("❌ ค่าของระบบ E1 / N1 / N2 / N4 / N9 ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpPartial_R <= 0.0 || InpPartial_Pct < 0.0 || InpPartial_Pct > 100.0 || InpChand_Sigma < 0.0 || InpTimeCut_Min < 0) {
      Print("❌ ค่าจัดการไม้ A-Survival ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpPostTrack_Min < 1 || InpPostTrack_Min > 1440) { Print("❌ InpPostTrack_Min ต้องอยู่ระหว่าง 1-1440"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpSigmaFloorMult < 0.0 || InpNewsBlock_Min < 0) { Print("❌ ค่าพื้นตัวหาร / ช่วงข่าว ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Print("❌ EA นี้ต้องใช้บัญชีแบบ Hedging (บัญชี Netting จะรวมไม้เป็นโพซิชันเดียว)");
      return(INIT_FAILED);
   }

   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   g_draw  = !(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
   if(NormalizeLot(InpSysLot * InpPartial_Pct / 100.0) >= NormalizeLot(InpSysLot))
      PrintFormat("ℹ️ Lot %.2f แบ่งปิด %.0f%% ไม่ได้ — ถึง %.1fR จะเลื่อน SL บังทุนอย่างเดียว", InpSysLot, InpPartial_Pct, InpPartial_R);

   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints((ulong)MathMax(0.0, PtsToPrice(InpSlippage_Pts) / _Point));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_session_ok = BuildWeekBlocks();
   if(!g_session_ok) Print("⚠️ อ่านเวลา Session ของ Symbol ไม่ได้ — ปิดการกรองเวลาตลาด");
   if(InpNewsFilter && MQLInfoInteger(MQL_TESTER)) Print("ℹ️ ปฏิทินข่าวใช้ไม่ได้ใน Strategy Tester — ไม่กรองช่วงข่าว");
   if(StringFind(_Symbol, "XAU") < 0) PrintFormat("⚠️ EA ออกแบบสำหรับ XAUUSD แต่กำลังรันบน %s", _Symbol);

   g_sys_clr[SYS_T4] = clrViolet;     g_sys_clr[SYS_E1] = clrGold;      g_sys_clr[SYS_N1] = clrOrange;
   g_sys_clr[SYS_N2] = clrDodgerBlue; g_sys_clr[SYS_N4] = clrMagenta;   g_sys_clr[SYS_N9] = clrSpringGreen;

   g_barz_bar = 0;
   ArrayResize(g_zl_names, 0);
   ArrayResize(g_zl_times, 0);
   g_bar_changed   = false;
   g_last_tick_msc = 0;
   g_zc.ok         = false;
   g_lv.Reset();
   ReplayReset();
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_news_loaded    = 0;
   g_news_ok        = false;
   g_prev_close_zr  = 0.0;
   g_prev_close_zs  = 0.0;
   ArrayResize(g_marks, 0);
   g_marks_bar = 0;
   g_mem_bar   = 0;
   g_newsviz_loaded = 0;
   ArrayResize(g_newsviz_names, 0);
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   g_last_comment   = "";
   g_line_main = g_line_sell = g_line_buy = 0.0;
   g_line_sma_main = g_line_sma_sell = g_line_sma_buy = 0.0;
   g_live_z_text = ""; g_live_z_y = -1;

   RefreshNews(ServerNow());
   SysEnableInit();
   g_lay_sig = "";
   LiveRestore();
   LiveMemRebuild();

   ObjectsDeleteAll(0, OBJ_PREFIX);
   LoadEntryMarksFromHistory();
   DrawSysButtons();

   EventSetTimer(1);
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
   if(!UpdateZ(tk.bid)) return;
   UpdateLiveZLabel(tk.bid);
   datetime now = ServerNow();
   int      ts  = GetTimeState(now);
   g_lv.Step(g_last_tick_msc, tk.bid, tk.ask, true, g_zc, g_bar0_hi, g_bar0_lo, ts, EntryBlockReason(ts, tk.bid, tk.ask, now));
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);
   LiveSync();
   LiveMemRebuild();

   // จัดการไม้ / จุด A หมดอายุ / ตัดเวลา แม้ไม่มี Tick เข้า (ราคา / Z ยังเป็นค่าล่าสุด)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   zok = (bid > 0.0 && ask > 0.0 && UpdateZ(bid));
   if(zok) g_lv.Step(MathMax(g_last_tick_msc, (long)now * 1000), bid, ask, false, g_zc, g_bar0_hi, g_bar0_lo, ts,
                     EntryBlockReason(ts, bid, ask, now));

   if(g_draw) {
      UpdateZLines();
      UpdateBarZLabels();
      UpdateEntryMarks();
      ReplayStep();
      LayoutTradeLabels();
      LoadNewsHistory();
      if(bid > 0.0) UpdateLiveZLabel(bid);
      UpdateDashboard(ts, now);
      ChartRedraw(0);
   }
}

// คลิกปุ่มระบบ → เปิด/ปิด | เลื่อน/ซูม/ย่อขยายกราฟ → จัดตำแหน่งป้าย Z สด + ป้ายไม้ใหม่ทันที
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BTN_PREFIX) == 0) {
      ToggleSys((int)StringToInteger(StringSubstr(sparam, StringLen(BTN_PREFIX))));
      ChartRedraw(0);
      return;
   }
   if(id != CHARTEVENT_CHART_CHANGE || !g_draw) return;
   LayoutTradeLabels();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid > 0.0) {
      g_live_z_y = -1;
      UpdateLiveZLabel(bid);
      ChartRedraw(0);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   AddEntryMarkFromDeal(trans.deal);
}
//+------------------------------------------------------------------+
