//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Fast Mean-Reversion Z-Score EA for XAUUSD (Indicator v8.82)  |
//+------------------------------------------------------------------+
//
// 🎯 นิยามระบบ (v12)
//  ค่า Z ที่สุดขั้วเกินจริงมักถูกดีดกลับเสมอ (แม้เป็นเทรนด์จริง) → สวนกลับอย่างเดียว ครั้งละ 1 ไม้
//  (ประวัติการเปลี่ยนแปลงทุกเวอร์ชันอยู่ใน README.md)
//
// 📐 Z-Score (TF ของ Z, 20 แท่ง, รวมแท่งปัจจุบันที่ราคา Bid)
//  • Z_reg = (ราคา − เส้นถดถอยเชิงเส้น) / max(StdDev รอบเส้นถดถอย, 0.5 × StdDev ของส่วนต่างราคาต่อแท่ง)
//  • Z_SMA = (ราคา − SMA20) / StdDev20
//
// 📋 ตรรกะการเข้าไม้ (v12.60) — ตรวจ T4 → T3 → T2, เกณฑ์เดียวกันทั้ง SELL (+Z) / BUY (−Z), เปิด/ปิดแต่ละระดับด้วยปุ่มบนกราฟ
//  • T4: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > 3.5 → ยิงทันที (Lot 0.04)
//  • T3: Z ตัวใดตัวหนึ่ง > 3.0 + ไม่มีค่าสุดขั้วใหม่ 2 วิ (Lot 0.03)
//  • T2: Z ทั้งคู่ > 2.5 (แท่งลอย Z_float > 2.0 → ตัวใดตัวหนึ่งก็ได้) + 5 วิ (Lot 0.02)
//    ระดับที่ปิดอยู่ = ข้ามไปตรวจระดับถัดลงมา (เช่น ปิด T4 → Z > 3.5 นับเป็น T3)
//  • T2 ต้องเป็นแท่งลอย Z_float > 1.8 (ราคาเปิดแท่ง − SMA ตอนเปิดแท่ง) ÷ SD20 — T3 / T4 ไม่ต้องลอย
//  • "ไม่มีค่าสุดขั้วใหม่" นับจากราคา (Bid ทำ High ใหม่ฝั่ง SELL / Low ใหม่ฝั่ง BUY เกิน 100 จุด) ไม่ใช่จาก Z
//    เพราะ Z_SMA มีเพดาน √(n−1) = 4.36 → ใกล้เพดานราคาวิ่งต่อได้มากแต่ Z แทบไม่ขยับ
//  • โหมด LH (ปุ่ม LH ON/OFF): ยิงเฉพาะตอนยืนยันโหนดที่ "ยอดที่สองต่ำกว่ายอดแรก" ≥ 0.10 Z (Z สุดขั้วของการเฝ้า − Z ที่โหนด)
//    แทนตัวจับเวลา (ทุกระดับรวม T4) — ปิดอยู่ = ใช้ตัวจับเวลาตามเดิม
//  • Z* = Z_SMA แบบไม่มีเพดาน = Z · √(n ÷ (n − 1 − Z²)) (ระยะจากค่าเฉลี่ย 19 แท่งก่อน ÷ SD ของ 19 แท่งนั้น) — แสดง + บันทึก
//  • ระหว่างจับเวลา Z หลุดเกณฑ์ได้ (ไม่ยกเลิก, ใช้ระดับลึกสุดที่ไปถึง) — ยกเลิกเมื่อขึ้นแท่งใหม่ / เข้าช่วงห้าม
//    + การเฝ้าระดับ T2: Z ตัวใดตัวหนึ่งกลับถึง 0 (เส้นกลาง) → ยกเลิกแล้วรอสัญญาณใหม่
//    มีไม้ถืออยู่ = ยังเฝ้าต่อแต่ยังไม่ยิง (ครั้งละ 1 ไม้), ไม้ปิด = ล้างการเฝ้าฝั่งเดียวกัน
//  • กฎในแท่ง (แยกฝั่ง): ไม้ T2 ชน SL ในแท่งไหน (ไม่ว่าเปิดแท่งไหน) → ปิด T2 ฝั่งนั้นที่เหลือของแท่ง (T3 / T4 ลุยต่อ)
//    T3 / T4 ชน SL → เปิดใหม่ได้ทันทีถ้า Z สุดขั้วมากกว่าไม้ที่ชน SL อย่างน้อย 0.1 (แท่งใหม่ล้างค่า)
//  • ห้ามเฝ้า/เข้าไม้: นาทีแรก + 2 นาทีสุดท้ายของแท่ง, ข่าว USD High ±5 นาที | ตัวกรองตอนยิง: เวลาตลาด + สเปรด | ไม่มี Cool down
//  • บันทึก (ไม่กรอง): Z_open = (Open − SMA) ÷ SD20, Z_gap = (เส้นถดถอย − SMA) ÷ SD20 (+ = ทิศของการกระชาก)
//  • โหนด (แสดง + บันทึก ไม่มีผลกับการเทรด): ระหว่างเฝ้า T2-T4 fit พาราโบลาบนราคา 15 วิล่าสุด (ทีละ 1 วิ)
//    → อนุพันธ์อันดับ 1 = 0 (จุดยอด) + อันดับ 2 < 0 (ยอด SELL) / > 0 (ก้น BUY) + R² ≥ 0.5 = โหนด "N1 Z+3.12"
//
// 📋 ตรรกะการจัดการไม้
//  • SL = High (SELL) / Low (BUY) ของแท่ง (TF ของ Z) ณ ตอนเปิดไม้ ± 500 จุด (ทุกระดับ), TP 30,000 จุด
//  • กำไรถึง 10,000 → เปิดโล่ไล่จี้ (ห่าง 8,000 ขยับทุก 5 วิ) แล้วปล่อยให้โล่ทำงาน
//  • ยังไม่ถึงโล่: กำไรคืนเกิน 75% จากกำไรสูงสุด (สูงสุด ≥ 2,000) → ตัดจบ / ครบ 1,500 วิ → ตัดจบ
//  • ห้ามเข้า 1 ชม.แรกหลังตลาดเปิดสัปดาห์ / ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//
// 🧪 Tick Replay (บนกราฟ, ไม่ใช่ Strategy Tester)
//  • เล่นซ้ำ tick จริงย้อนหลังด้วยกติกาเดียวกับ EA (รวมตัวกรองข่าว) → มาร์กบนกราฟ + สรุปบน Dashboard
//  • บันทึกปัจจัย "ใช่ยอดหรือยัง" ณ ตอนยิง + ระยะกำไรระหว่างถือ (ต่ำสุด / สูงสุด / เฉลี่ย) → MQL5/Files/7LCEA_Replay_<symbol>.csv
//    A ระยะฉีกจาก High / Low ของ 2 แท่งก่อน ÷ ช่วงแท่งเฉลี่ย 20 แท่ง | B แรงส่ง 30 วิล่าสุด เทียบ 30 วิก่อนหน้า
//    C Z ลดจากค่าสุดขั้ว | D ถอยจากยอดเทียบระยะฉีก | E อัตรา tick 15 วิล่าสุด เทียบ 60 วิก่อนหน้า
//  (เส้นบริบท VWAP / Keltner / TF ใหญ่ / วันก่อน / EMA ยาว แยกไปอยู่ใน Indicators/Seven_Lines_Context_Ind.mq5)
//
// ⚡ การประหยัด CPU
//  • Z: แคชผลรวมของแท่งที่ปิดแล้ว คำนวณใหม่เฉพาะตอนขึ้นแท่งใหม่ (ต่อ Tick ไม่กี่บรรทัดคณิต)
//  • จัดการไม้ / Dashboard / เส้น ทำบน OnTimer 1 วินาที, นับ SL ติดต่อกันผ่าน OnTradeTransaction
//  • Dashboard เขียนเฉพาะเมื่อข้อความเปลี่ยน, ไม่วาดอะไรใน Tester แบบไม่เปิด Visual
//
#property copyright   "Commander's Quant System"
#property version     "12.90"
#property description "สวนกลับค่า Z ผิดปกติที่ควรดีดกลับเร็ว สำหรับ XAUUSD (บัญชี Hedging)"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score & จุดเข้า (สวนกลับ, เกณฑ์เดียวกันทั้ง SELL / BUY) ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input bool            InpEnableT2          = true;       // เปิดใช้ T2 (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ)
input bool            InpEnableT3          = true;       // เปิดใช้ T3 (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ)
input bool            InpEnableT4          = true;       // เปิดใช้ T4 (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ)
input double          InpT2_Z              = 2.50;       // T2: Z_reg และ Z_SMA ทั้งคู่ > ค่านี้ (SELL +Z / BUY −Z)
input double          InpT2EitherFloat     = 2.00;       // T2: แท่งลอย Z_float > ค่านี้ → Z ตัวใดตัวหนึ่ง > T2 ก็ได้ (ตั้งสูง เช่น 99 = ต้องทั้งคู่เสมอ)
input int             InpT2_Sec            = 5;          // T2: ยิงเมื่อไม่มีค่าสุดขั้วใหม่ครบกี่วินาที
input double          InpT3_Z              = 3.00;       // T3: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ (ไม่ต้องลอย)
input int             InpT3_Sec            = 2;          // T3: ยิงเมื่อไม่มีค่าสุดขั้วใหม่ครบกี่วินาที
input bool            InpEnableLH          = false;      // โหมด LH: ยิงเมื่อยืนยันโหนดที่ต่ำกว่ายอดของการเฝ้า (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ)
input double          InpLH_MinZ           = 0.10;       // โหมด LH: ยอดที่สอง (โหนด) ต้องต่ำกว่ายอดแรก (Z สุดขั้วของการเฝ้า) อย่างน้อยกี่ Z
input double          InpT4_Z              = 3.50;       // T4: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ → ยิงทันที (ไม่ต้องลอย)
input bool            InpFloatFilter       = true;       // T2 ต้องเป็นแท่งลอยตัว: ราคาเปิดแท่งพ้นเส้น SMA ตอนเปิดแท่ง (SELL เหนือ / BUY ใต้)
input double          InpFloatMin          = 1.80;       // T2 ทำงานเมื่อแท่งลอย Z_float > ค่านี้ (หน่วย SD20, 0 = แค่ราคาเปิดพ้น SMA)
input double          InpNoNewExt_Pts      = 100.0;      // ราคาต้องเกิน High (SELL) / Low (BUY) เดิมระหว่างเฝ้าเท่านี้ถึงนับเป็นค่าสุดขั้วใหม่ (จุด)
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot ฐาน (T2 = ฐาน + step = 0.02)
input double          InpTierLotStep       = 0.01;       // Lot เพิ่มต่อระดับ (T2 = ฐาน+step, T3 = +2·step, T4 = +3·step)
input double          InpTP_Pts            = 30000.0;    // Take Profit (จุด)
input double          InpSLPeak_Pts        = 500.0;      // SL = High (SELL) / Low (BUY) ของแท่ง (TF ของ Z) ณ ตอนเปิดไม้ ± ระยะนี้ (จุด, ทุกระดับ)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์ (ต่อท้ายด้วยระดับ / Z สุดขั้ว ใช้คืนค่ากฎในแท่งเมื่อรีสตาร์ท)

input group "=== 3. ไล่จี้กำไร ==="
input double          InpTrailStart_Pts    = 10000.0;    // เริ่มไล่จี้เมื่อกำไรถึง (จุด)
input double          InpTrailDist_Pts     = 8000.0;     // ระยะโล่ห่างจากราคา (จุด)
input int             InpTrailInterval_Sec = 5;          // ขยับโล่ทุกกี่วินาที (หลังเริ่มไล่จี้แล้ว)

input group "=== 4. ตัดจบ / เวลาในแท่ง ==="
input int             InpQuickWindow_Sec   = 1500;       // ทุกไม้ต้องเข้าระบบไล่จี้ภายในกี่วินาที ไม่งั้นตัดจบ (0 = ปิด)
input double          InpGiveback_Pct      = 75.0;       // ยังไม่ถึงโล่: กำไรคืนเกินกี่ % จากกำไรสูงสุด → ตัดจบ (0 = ปิด)
input double          InpGivebackMinPeak_Pts = 2000.0;   // ใช้กฎคืนกำไรเมื่อกำไรสูงสุดถึงอย่างน้อยกี่จุด
input int             InpBarStartDelay_Sec = 60;         // ห้ามเฝ้า / เปิดไม้ ช่วงกี่วินาทีแรกของแท่ง (TF ของ Z)
input int             InpBarEndBlock_Sec   = 120;        // ห้ามเฝ้า / เปิดไม้ ช่วงกี่วินาทีสุดท้ายก่อนปิดแท่ง (0 = ปิด)

input group "=== 5. กฎในแท่ง (แยกฝั่ง, แท่งใหม่ล้างค่า) ==="
input bool            InpT2BlockOnSL       = true;       // ไม้ T2 ชน SL ในแท่งไหน → ปิด T2 ฝั่งนั้นที่เหลือของแท่ง
input double          InpReEntryZStep      = 0.10;       // T3 / T4 ชน SL → ไม้ใหม่ต้อง Z สุดขั้วมากกว่าไม้ที่ชน SL อย่างน้อยเท่านี้

input group "=== 6. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input bool            InpNewsFilter        = true;       // งดเฝ้า / เข้าไม้ช่วงข่าว High (ไม้ที่ถืออยู่รันต่อ, ใช้ไม่ได้ใน Tester)
input int             InpNewsBlock_Min     = 5;          // งดก่อน / หลังเวลาข่าวออกกี่นาที
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าว (กรอง + แสดง)

input group "=== 7. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowZLines        = true;       // แสดงเส้นแนวนอนระดับ Z ชุด Regression
input bool            InpShowSmaZLines     = true;       // แสดงเส้นแนวนอนระดับ Z ชุด SMA20 (เปรียบเทียบ)
input bool            InpShow7Lines        = true;       // วาดเส้น 7 เส้น (คำนวณในตัว EA บน TF ของกราฟ)
input int             InpFastPeriod        = 10;         // Fast Period ของเส้น L1-L5
input int             InpLinesBars         = 200;        // จำนวนแท่งย้อนหลังที่วาดเส้น 7 เส้น
input bool            InpShowLineMain      = true;       // เส้น 7 เส้น: แสดง Main (SMA)
input bool            InpShowLineFast      = false;      // เส้น 7 เส้น: แสดงเส้นเร็ว L1-L6 (EMA / LWMA / HMA / LSMA / ALMA / Kinematic)
input bool            InpShowLiveZ         = true;       // แสดงป้ายค่า Z สด ณ ราคาปัจจุบัน
input int             InpLiveZFontSize     = 11;         // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;         // ระยะห่างป้าย Z สดจากขอบขวาของกราฟ (พิกเซล)
input bool            InpShowBarZ          = true;       // แสดงป้ายค่า Z บนแท่งที่ Z ถึงเกณฑ์
input bool            InpShowFloatMark     = true;       // แสดงป้าย Z_float บนแท่งที่ราคาเปิดลอยพ้น SMA (ช่วงแท่งเดียวกับป้าย Z)
input double          InpFloatMarkZ        = 1.00;       // ป้าย Z_float: แสดงเมื่อ Z_float > ค่านี้
input bool            InpFloatMarkLive     = true;       // ป้าย Z_float: แท่งปัจจุบันแสดงค่าเสมอตั้งแต่เปิดแท่ง (ไม่ถึงเกณฑ์ = สีเทา)
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย (สูงสุด 20,000)
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กสัญญาณที่ถูกตัวกรองทิ้ง
input bool            InpReplayCSV         = true;       // Tick Replay: บันทึกปัจจัยตอนยิง + ผล + ระยะกำไรระหว่างถือ ลง CSV (MQL5/Files)
input int             InpPostTrack_Min     = 60;         // Tick Replay: ติดตามต่อหลังเข้าไม้กี่นาที (แม้ไม้ปิดแล้ว) → Z สูงสุด / ระยะสวน / เวลากลับถึง Z
input double          InpPostBackZ         = 1.00;       // Tick Replay: นับเวลาจนกว่า Z_SMA (ทิศของการกระชาก) กลับถึงค่านี้
input bool            InpShowNodes         = true;       // โหนด: จุดที่ราคาหยุดพุ่ง (อนุพันธ์ 1 = 0, อนุพันธ์ 2 ถูกทิศ) ระหว่างเฝ้า T2-T4
input int             InpNodeWindow_Sec    = 15;         // โหนด: หน้าต่าง fit พาราโบลา (วินาที, 5-60)
input double          InpNodeMinR2         = 0.50;       // โหนด: R² ของการ fit ขั้นต่ำ (กรองสัญญาณรบกวน, 0-1)
input int             InpNodeMinPast_Sec   = 1;          // โหนด: จุดยอดต้องผ่านมาแล้วอย่างน้อยกี่วินาที
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (ใช้ไม่ได้ใน Tester)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium บนกราฟด้วย (ไม่ใช้กรอง)

input group "=== 8. สี ==="
input color           InpClrMain           = clrGold;           // เส้น Main (SMA)
input color           InpClrL1             = clrDeepSkyBlue;    // เส้น L1 (EMA)
input color           InpClrL2             = clrDodgerBlue;     // เส้น L2 (LWMA)
input color           InpClrL3             = clrMagenta;        // เส้น L3 (HMA)
input color           InpClrL4             = clrHotPink;        // เส้น L4 (LSMA)
input color           InpClrL5             = clrMediumSeaGreen; // เส้น L5 (ALMA)
input color           InpClrL6             = clrOrange;         // เส้น L6 (Kinematic)
input color           InpClrZCenter        = clrGold;           // เส้นแนวนอน: เส้นกลาง Z = 0
input color           InpClrZSellLine      = clrOrangeRed;      // เส้นแนวนอน: ระดับ SELL
input color           InpClrZBuyLine       = clrAqua;           // เส้นแนวนอน: ระดับ BUY
input color           InpClrSmaCenter      = clrDarkKhaki;      // เส้นแนวนอน SMA20: เส้นกลาง Z = 0
input color           InpClrSmaSellLine    = clrLightSalmon;    // เส้นแนวนอน SMA20: ระดับ SELL
input color           InpClrSmaBuyLine     = clrPaleTurquoise;  // เส้นแนวนอน SMA20: ระดับ BUY
input color           InpClrLiveSell       = clrOrangeRed;      // ป้าย Z สด: ถึงเกณฑ์ SELL
input color           InpClrLiveBuy        = clrDeepSkyBlue;    // ป้าย Z สด: ถึงเกณฑ์ BUY
input color           InpClrLiveNear       = clrGold;           // ป้าย Z สด: ใกล้เกณฑ์
input color           InpClrLiveNormal     = clrSilver;         // ป้าย Z สด: ปกติ
input color           InpClrBarZSell       = clrOrangeRed;      // ป้าย Z บนแท่ง: ฝั่ง SELL (เหนือแท่ง)
input color           InpClrBarZBuy        = clrDeepSkyBlue;    // ป้าย Z บนแท่ง: ฝั่ง BUY (ใต้แท่ง)
input color           InpClrBarZOther      = clrGray;           // ป้าย Z บนแท่ง: ถึงเกณฑ์ไม่ครบตามเงื่อนไขเข้าไม้
input color           InpClrFloatMark      = clrMediumPurple;   // ป้าย Z_float (แท่งลอยพ้น SMA)
input color           InpClrEntrySell      = clrRed;            // มาร์กจุดเปิด SELL
input color           InpClrEntryBuy       = clrLime;           // มาร์กจุดเปิด BUY
input color           InpClrEntryGap       = clrYellow;         // เส้นประ + ตัวเลขระยะห่างถึงปลายไส้
input color           InpClrSimSell        = clrViolet;         // มาร์กจำลอง: SELL
input color           InpClrSimBuy         = clrPaleGreen;      // มาร์กจำลอง: BUY
input color           InpClrSimWin         = clrLimeGreen;      // มาร์กจำลอง: เส้นเข้า→ออก ไม้กำไร
input color           InpClrSimLoss        = clrTomato;         // มาร์กจำลอง: เส้นเข้า→ออก ไม้ขาดทุน
input color           InpClrSimBlocked     = clrDimGray;        // มาร์กจำลอง: สัญญาณที่ถูกตัวกรองทิ้ง
input color           InpClrNodeSell       = clrOrange;         // โหนด: ยอด (ฝั่ง SELL)
input color           InpClrNodeBuy        = clrTurquoise;      // โหนด: ก้น (ฝั่ง BUY)
input color           InpClrNewsLine       = clrMediumPurple;   // เส้นเวลาข่าว
input color           InpClrNewsZone       = C'45,35,70';       // แถบแท่งข่าว

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
const string LABEL_LIVE_Z   = "7LCEA_LIVE_Z";
const string LINE_SMA_MAIN  = "7LCEA_SMA_MAIN";
const string LINE_SMA_SELL  = "7LCEA_SMA_SELL_Z";
const string LINE_SMA_BUY   = "7LCEA_SMA_BUY_Z";
const long   WEEK_SEC       = 604800;
const long   DAY_SEC        = 86400;
const long   MERGE_GAP_SEC  = 12 * 3600;   // ช่องว่าง session สั้นกว่านี้ (เช่นพักรายวัน) ถือว่าตลาดยังเปิด

struct WeekBlock {
   long s;   // วินาทีนับจากวันอาทิตย์ 00:00 (เวลาเซิร์ฟเวอร์)
   long e;
};

// สถานะเฝ้าค่าสุดขั้ว (No new high/low) ของแต่ละฝั่ง — ใช้ร่วมกันทั้ง EA จริงและ Tick Replay
struct WatchState {
   bool   active;
   int    tier;       // ระดับลึกสุดที่ไปถึงระหว่างเฝ้า (1-4) → เวลารอ / Lot (Z หลุดเกณฑ์ได้ ไม่ลดระดับ)
   int    max_tier;   // = tier (เก็บไว้แสดงผล)
   double ext_r;      // ค่าสุดขั้วของ Z_reg ระหว่างเฝ้า
   double ext_s;      // ค่าสุดขั้วของ Z_SMA ระหว่างเฝ้า
   long   last_new;   // เวลา (msc) ที่ทำค่าสุดขั้วใหม่ล่าสุด
   long   started;    // เวลา (msc) ที่เริ่มเฝ้า
   double start_px;   // ราคาตอนเริ่มเฝ้า
   double ext_px;     // ราคาสุดขั้วระหว่างเฝ้า (Bid สูงสุด SELL / ต่ำสุด BUY) — ตัวนับเวลา "ไม่มีค่าใหม่"
};

// กฎในแท่งของแต่ละฝั่ง — ใช้ร่วมกันทั้ง EA จริงและ Tick Replay (แท่งใหม่ล้างค่า)
struct SideGate {
   datetime bar;          // แท่ง (TF ของ Z) ที่ค่านี้ใช้อยู่
   bool     t2_block;     // ไม้ T2 ชน SL ในแท่งนี้ → ปิด T2 ที่เหลือของแท่ง
   double   re_z;         // T3 / T4 ชน SL → ไม้ T3 / T4 ใหม่ต้อง Z สุดขั้ว > ค่านี้ + InpReEntryZStep (0 = ไม่มี)
};

// แคชผลรวมของแท่งที่ปิดแล้ว (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct ZCache {
   bool   ok;
   double ref, sY, sXY, sYY, sD, sDD, last_close;
   double prev_zr, prev_zs;   // Z ตอนปิดแท่งล่าสุด
};

const double NEAR_ZONE = 0.5;   // ระยะ "ใกล้เกณฑ์" สำหรับสีป้าย Z

CTrade    trade;
double    g_pmult        = 1.0;
bool      g_draw         = true;

// --- Z engine (แคชผลรวมของแท่งที่ปิดแล้ว, ค่าเลื่อนจุดอ้างอิง g_ref) ---
datetime  g_zbar_time    = 0;
bool      g_z_ready      = false;
double    g_ref          = 0.0;
bool      g_z_valid      = false;
double    g_z            = 0.0;   // Z สำหรับสีป้าย (ตัวที่ห่าง 0 มากกว่า)
double    g_z_reg        = 0.0;   // Regression Z
double    g_center       = 0.0;   // ราคาเส้นกลาง Regression (เส้นถดถอยที่แท่งปัจจุบัน)
double    g_sigma        = 0.0;   // ตัวหาร Regression ที่ใช้จริง
double    g_sma_mean     = 0.0;   // ราคา SMA20 (รวมแท่งปัจจุบัน)
double    g_sma_sd       = 0.0;   // StdDev20
bool      g_sigma_floor  = false; // ตัวหารถูกยกขึ้นเป็นพื้นขั้นต่ำ
double    g_z_sma        = 0.0;   // Z แบบ SMA เดิม (แสดงเทียบ)
double    g_prev_close_zr = 0.0;  // Regression Z ของแท่งที่เพิ่งปิด
double    g_prev_close_zs = 0.0;  // SMA Z ของแท่งที่เพิ่งปิด

// --- ช่วงแกว่งแท่งปัจจุบัน / ข่าว ---
double    g_bar0_hi      = 0.0;
double    g_bar0_lo      = 0.0;
double    g_bar0_open    = 0.0;
double    g_bar0_fz      = 0.0;   // (ราคาเปิด − SMA ตอนเปิดแท่ง) ÷ SD20 ของแท่งปัจจุบัน (+ = เหนือ SMA)
double    g_bar0_fsma    = 0.0;   // SMA / SD20 ตอนเปิดแท่ง
double    g_bar0_fsd     = 0.0;
datetime  g_news_times[];             // ข่าว High (เรียงเวลา) ตั้งแต่ช่วง Tick Replay ถึง +24 ชม.
string    g_news_names[];
datetime  g_news_loaded  = 0;
bool      g_news_ok      = false;   // โหลดปฏิทินข่าวสำเร็จแล้วอย่างน้อย 1 ครั้ง

// --- เฝ้าค่าสุดขั้ว / กฎในแท่ง (EA จริง) ---
WatchState g_wsell;
WatchState g_wbuy;
SideGate   g_gs;                       // กฎในแท่งฝั่ง SELL / BUY
SideGate   g_gb;
SideGate   g_gate_none;                // ไม่มีข้อจำกัด (ป้าย Z บนแท่ง)
bool       g_en[5];                    // เปิดใช้ระดับ T2-T4 (ปุ่มบนกราฟ, index = ระดับ)
bool       g_lh_on          = false;   // โหมด LH (ปุ่มบนกราฟ)
bool       g_lh_sig_s       = false;   // EA จริง: เพิ่งยืนยันโหนด LH ฝั่ง SELL / BUY (ใช้ได้รอบเดียว)
bool       g_lh_sig_b       = false;
string     g_lay_sig        = "";      // สถานะกราฟตอนจัดป้ายไม้ล่าสุด
bool       g_bar_changed    = false;   // ขึ้นแท่งใหม่ (TF ของ Z) → ล้างการเฝ้า
long       g_last_tick_msc  = 0;
datetime   g_next_try       = 0;
string     g_last_status    = "เริ่มทำงาน";
ulong      g_activated[];              // ไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว
ulong      g_peak_tk[];                // กำไรสูงสุดของแต่ละไม้ (ราคา) สำหรับกฎคืนกำไร
double     g_peak_px[];
datetime   g_gb_retry       = 0;       // ปิดตามกฎคืนกำไรไม่สำเร็จ → ลองใหม่หลังเวลานี้

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
double    g_line_sma_main = 0.0;
double    g_line_sma_sell = 0.0;
double    g_line_sma_buy  = 0.0;
string    g_live_z_text  = "";
int       g_live_z_y     = -1;

// --- เส้น 7 เส้น (TF ของกราฟ, เรียงเก่า→ใหม่) ---
double    g_lc[];                 // ราคาปิด (แท่งสุดท้าย = แท่งปัจจุบัน)
datetime  g_lt[];                 // เวลาแท่ง
double    g_lv[][7];              // ค่าเส้นทั้ง 7 ต่อแท่ง
int       g_lines_total  = 0;
int       g_lines_warm   = 0;     // ดัชนีแรกที่เส้น 2-7 คำนวณได้ครบ
datetime  g_lines_bar    = 0;     // เวลาแท่งปัจจุบันตอนคำนวณชุดล่าสุด
string    g_lines_status = "ยังไม่ได้วาด";
double    g_alma_w[];
double    g_alma_wsum    = 0.0;

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

//--- กำไรสูงสุดของแต่ละไม้ (ราคา) สำหรับกฎคืนกำไร ---
double PeakOf(ulong ticket) {
   for(int i = ArraySize(g_peak_tk) - 1; i >= 0; i--)
      if(g_peak_tk[i] == ticket) return g_peak_px[i];
   return 0.0;
}

double PeakUpdate(ulong ticket, double prof) {
   int n = ArraySize(g_peak_tk);
   for(int i = 0; i < n; i++)
      if(g_peak_tk[i] == ticket) { if(prof > g_peak_px[i]) g_peak_px[i] = prof; return g_peak_px[i]; }
   ArrayResize(g_peak_tk, n + 1);
   ArrayResize(g_peak_px, n + 1);
   g_peak_tk[n] = ticket;
   g_peak_px[n] = MathMax(0.0, prof);
   return g_peak_px[n];
}

void PrunePeaks() {
   int n = ArraySize(g_peak_tk), w = 0;
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(g_peak_tk[i])) { g_peak_tk[w] = g_peak_tk[i]; g_peak_px[w] = g_peak_px[i]; w++; }
   if(w != n) { ArrayResize(g_peak_tk, w); ArrayResize(g_peak_px, w); }
}

// กฎคืนกำไร (ใช้ร่วมกัน): กำไรสูงสุดยังไม่ถึงจุดเริ่มไล่จี้ แต่ถึง InpGivebackMinPeak_Pts
//   และกำไรตอนนี้คืนเกิน InpGiveback_Pct% จากจุดสูงสุด → ตัดจบ (peak / prof เป็นระยะราคา)
bool GivebackHit(double peak, double prof) {
   if(InpGiveback_Pct <= 0.0 || peak <= 0.0) return false;
   if(peak < PtsToPrice(InpGivebackMinPeak_Pts) || peak >= PtsToPrice(InpTrailStart_Pts)) return false;
   return prof <= peak * (1.0 - InpGiveback_Pct / 100.0);
}

//====================================================================
// 🧮 Z สำหรับสีป้าย: ตัวที่ห่าง 0 มากกว่า (เข้าไม้ใช้ Z ตัวใดตัวหนึ่ง)
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

// ระยะของราคาเปิด / เส้นถดถอย จาก SMA ÷ SD (+ = ทิศของการกระชาก: SELL เหนือ SMA, BUY ใต้ SMA)
double ZFromSMA(int dir, double px, double sma, double sd) {
   if(sd <= 0.0) return 0.0;
   return (dir == -1) ? (px - sma) / sd : (sma - px) / sd;
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
//   เส้นถดถอย y = a + b·x, ส่วนเบี่ยงเบน SSR = Σy² − aΣy − bΣxy
//   Z_reg = (y_ปัจจุบัน − เส้นถดถอยที่ x=n-1) / max(σ_residual, FloorMult × σ_ส่วนต่างต่อแท่ง)
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
// 🎯 SIGNAL: เฝ้าค่าสุดขั้ว No new high/low + กฎในแท่ง (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
// แท่ง (TF ของ Z) ที่เวลา t อยู่
datetime BarStartOf(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   return (per > 0) ? (datetime)((long)t - (long)t % per) : t;
}

// Z สุดขั้วในทิศของการกระชาก (ตัวที่สูงกว่าระหว่าง Z_reg / Z_SMA)
double ZHi(int dir, double zr, double zs) { return MathMax((dir == -1) ? zr : -zr, (dir == -1) ? zs : -zs); }

//--- กฎในแท่ง ---
void GateSync(SideGate &g, datetime bar) {
   if(g.bar == bar) return;
   g.bar = bar; g.t2_block = false; g.re_z = 0.0;
}

// ไม้ปิด → true = กฎในแท่งเปลี่ยน — ใช้กับแท่งที่ชน SL (ไม่ว่าไม้เปิดในแท่งไหน)
bool GateOnClose(SideGate &g, int tier, double ext_z, datetime bar_out, bool sl_loss) {
   GateSync(g, bar_out);
   if(!sl_loss) return false;
   if(tier >= 3) { g.re_z = MathMax(g.re_z, ext_z); return true; }
   if(InpT2BlockOnSL && tier == 2) { g.t2_block = true; return true; }
   return false;
}

// ระดับวิกฤต (ตรวจ T4 → T3 → T2, ข้ามระดับที่ปิดด้วยปุ่ม), zf = Z_float ในทิศของฝั่งนี้, g = กฎในแท่งของฝั่งนี้:
//   4 = Z ตัวใดตัวหนึ่ง > T4 | 3 = > T3 (T3 / T4 ไม่ต้องลอย, หลัง SL ต้อง Z > re_z + step)
//   2 = Z ทั้งคู่ > T2 (ตัวใดตัวหนึ่งเมื่อ zf > InpT2EitherFloat, ต้องลอย zf > InpFloatMin และไม่ถูกปิดในแท่ง) | 0 = ไม่ถึง
int TierOf(int dir, double zr, double zs, double zf, const SideGate &g) {
   double a_r = (dir == -1) ? zr : -zr;
   double a_s = (dir == -1) ? zs : -zs;
   double hi  = MathMax(a_r, a_s), lo = MathMin(a_r, a_s);
   bool   t34 = (g.re_z <= 0.0 || hi > g.re_z + InpReEntryZStep);
   if(g_en[4] && t34 && hi > InpT4_Z) return 4;
   if(g_en[3] && t34 && hi > InpT3_Z) return 3;
   if(!g_en[2] || g.t2_block || (InpFloatFilter && zf <= InpFloatMin)) return 0;
   if(lo > InpT2_Z || (hi > InpT2_Z && zf > InpT2EitherFloat)) return 2;
   return 0;
}

// เวลารอ (ไม่มีค่าสุดขั้วใหม่) ของแต่ละระดับ — T4 ยิงทันที
long TierWaitMs(int tier) {
   if(tier >= 4) return 0;
   return (long)(tier == 3 ? InpT3_Sec : InpT2_Sec) * 1000;
}

// Lot ตามระดับที่ยิง: T2 = InpLot + step, T3 = +2·step, T4 = +3·step
double TierLot(int tier) { return NormalizeLot(InpLot + (MathMax(1, tier) - 1) * InpTierLotStep); }

string StageTag(int tier) { return "T" + IntegerToString(tier); }

void WatchReset(WatchState &w) {
   w.active   = false;
   w.tier     = 0;
   w.max_tier = 0;
   w.ext_r    = 0.0;
   w.ext_s    = 0.0;
   w.last_new = 0;
   w.started  = 0;
   w.start_px = 0.0;
   w.ext_px   = 0.0;
}

// อัปเดตการเฝ้า: เริ่มเมื่อเข้าเงื่อนไขระดับใดระดับหนึ่ง, ราคาทำ High (SELL) / Low (BUY) ใหม่เกิน InpNoNewExt_Pts = นับเวลาใหม่
//   (Z สุดขั้วยังจำไว้สำหรับกฎในแท่ง / บันทึก แต่ไม่ใช้นับเวลา เพราะ Z_SMA อิ่มตัวใกล้เพดาน √(n−1)),
// ระดับ = ลึกสุดที่ไปถึง (Z หลุดเกณฑ์ระหว่างจับเวลาได้ ไม่ลดระดับ)
//   การเฝ้าระดับ T2: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่งกลับถึง 0 → ยกเลิกแล้วรอสัญญาณใหม่
//   zf = Z_float ในทิศของฝั่งนี้, g = กฎในแท่ง — ยกเลิกจากภายนอก: ขึ้นแท่งใหม่ / ช่วงห้าม / ไม้ปิด
void WatchUpdate(WatchState &w, int dir, double zr, double zs, long now_msc, double bid, double ask, double zf, const SideGate &g) {
   int tier = TierOf(dir, zr, zs, zf, g);
   if(!w.active) {
      if(tier < 1) return;
      WatchReset(w);
      w.active   = true;
      w.tier     = tier;
      w.max_tier = tier;
      w.ext_r    = zr;
      w.ext_s    = zs;
      w.last_new = now_msc;
      w.started  = now_msc;
      w.start_px = bid;
      w.ext_px   = bid;
      return;
   }
   if(dir == -1) { if(zr > w.ext_r) w.ext_r = zr; if(zs > w.ext_s) w.ext_s = zs; }
   else          { if(zr < w.ext_r) w.ext_r = zr; if(zs < w.ext_s) w.ext_s = zs; }
   double eps = PtsToPrice(InpNoNewExt_Pts);
   if(dir == -1 ? (bid > w.ext_px + eps) : (bid < w.ext_px - eps)) { w.ext_px = bid; w.last_new = now_msc; }
   if(tier > w.tier) w.tier = tier;
   w.max_tier = w.tier;
   double a_r = (dir == -1) ? zr : -zr, a_s = (dir == -1) ? zs : -zs;
   if(w.tier <= 2 && (a_r <= 0.0 || a_s <= 0.0)) WatchReset(w);   // T2: Z กลับถึงเส้นกลาง = สัญญาณจบ
}

long WatchDeadline(const WatchState &w) { return w.last_new + TierWaitMs(w.tier); }
bool WatchReady(const WatchState &w, long now_msc) { return w.active && now_msc >= WatchDeadline(w); }

//====================================================================
// 📈 โหนด: อนุพันธ์อันดับ 1 = 0, อันดับ 2 < 0 (ยอด SELL) / > 0 (ก้น BUY) ระหว่างเฝ้า T2-T4 — แสดง + บันทึก ไม่มีผลกับการเทรด
//   ราคา Bid สุดท้ายของทุกวินาที (วินาทีที่ไม่มี tick ใช้ราคาเดิม) → fit P(t) = a + b·t + c·t² บน InpNodeWindow_Sec วินาทีล่าสุด
//   (t = 0 คือวินาทีล่าสุดที่จบแล้ว) → จุดยอด t* = −b ÷ 2c, ค่าของโหนด = P(t*), d1 = P′(0) ÷ SD20, d2 = 2c ÷ SD20
//   นับเป็นโหนดเมื่อ: กำลังเฝ้าฝั่งนั้น + โค้งถูกทิศ + t* อยู่ในหน้าต่างและผ่านมาแล้ว ≥ InpNodeMinPast_Sec + R² ≥ InpNodeMinR2
//   โหนดถัดไปของฝั่งเดียวกันต้องรอให้ความชันกลับไปทางยอดก่อน (กันนับยอดเดิมซ้ำ), ลำดับโหนดนับใหม่ทุกแท่ง
//====================================================================
#define ND_MAXW 61

struct SecBuf {
   long   sec[ND_MAXW];   // วินาทีที่จบแล้ว (วนรอบ)
   double px[ND_MAXW];
   int    n;              // จำนวนที่มี
   int    head;           // ตำแหน่งที่จะเขียนถัดไป
   long   cur_sec;        // วินาทีที่กำลังเก็บ
   double cur_px;
};

struct NodeFit {
   bool   ok;
   long   sec0;           // วินาทีของ t = 0
   double b, c;           // P′(0) = b, P″ = 2c (ราคาต่อวินาที)
   double r2;
   double vt;             // t* (วินาที, ลบ = อดีต)
   double vpx;            // ราคาที่จุดยอด
};

struct NodeSide {
   datetime bar;          // แท่งที่นับลำดับโหนดอยู่
   bool     armed;        // พร้อมจับโหนดใหม่ (ความชันกลับไปทางยอดแล้ว)
   int      count;        // จำนวนโหนดของแท่งนี้
   long     v_msc;        // เวลาโหนดล่าสุด (จุดยอด)
   double   px;           // ราคาโหนดล่าสุด
   double   zr, zs;       // Z ที่โหนดล่าสุด
   double   ext_hi;       // Z สุดขั้ว (ตัวมากกว่า, ทิศของการกระชาก) ของการเฝ้า ณ เวลาโหนด
   double   ext_px;       // ราคาสุดขั้วของการเฝ้า ณ เวลาโหนด
};

struct NodeRec {
   long   v_msc;          // เวลาจุดยอด
   long   d_msc;          // เวลาที่ยืนยันโหนด
   int    dir;            // −1 = SELL (ยอด) / +1 = BUY (ก้น)
   int    tier;           // ระดับที่กำลังเฝ้า
   int    seq;            // โหนดที่เท่าไหร่ของแท่ง
   double px;             // ค่าของโหนด (ราคา)
   double zr, zs;         // Z ที่ราคาโหนด
   double d1, d2;         // Z/วิ, Z/วิ² ตอนยืนยัน (+ = ทิศของการกระชาก → โหนดปกติ d1 < 0, d2 < 0)
   double r2;
   double sd;             // SD20 ที่ราคาโหนด
   double ext_hi;         // Z สุดขั้วของการเฝ้า ณ เวลาโหนด (ทิศของการกระชาก)
   double ext_px;         // ราคาสุดขั้วของการเฝ้า ณ เวลาโหนด
};

SecBuf    g_lv_sb;                    // EA จริง
NodeFit   g_lv_fit;
NodeSide  g_lv_ns_s, g_lv_ns_b;
NodeRec   g_nd_lv[];
int       g_nd_lv_drawn = 0;

void SecReset(SecBuf &sb) { sb.n = 0; sb.head = 0; sb.cur_sec = 0; sb.cur_px = 0.0; }

void SecPush(SecBuf &sb, long sec, double px) {
   sb.sec[sb.head] = sec;
   sb.px[sb.head]  = px;
   sb.head = (sb.head + 1) % ND_MAXW;
   if(sb.n < ND_MAXW) sb.n++;
}

// ป้อนราคา → true เมื่อมีวินาทีจบเพิ่ม (ถึงเวลา fit ใหม่), ช่องว่างไม่มี tick เติมด้วยราคาเดิม
bool SecFeed(SecBuf &sb, long msc, double px) {
   long s = msc / 1000;
   if(sb.cur_sec == 0) { sb.cur_sec = s; sb.cur_px = px; return false; }
   if(s <= sb.cur_sec) { if(s == sb.cur_sec) sb.cur_px = px; return false; }
   SecPush(sb, sb.cur_sec, sb.cur_px);
   for(long k = MathMax(sb.cur_sec + 1, s - ND_MAXW); k < s; k++) SecPush(sb, k, sb.cur_px);
   sb.cur_sec = s;
   sb.cur_px  = px;
   return true;
}

// fit พาราโบลาบน w วินาทีล่าสุด (กำลังสองน้อยที่สุด, กฎของคราเมอร์)
bool NodeFitCalc(const SecBuf &sb, int w, NodeFit &f) {
   f.ok = false;
   if(sb.n < w) return false;
   int    last = (sb.head - 1 + ND_MAXW) % ND_MAXW;
   long   s0   = sb.sec[last];
   double p0   = sb.px[last];
   double S0 = 0.0, S1 = 0.0, S2 = 0.0, S3 = 0.0, S4 = 0.0, Y0 = 0.0, Y1 = 0.0, Y2 = 0.0, YY = 0.0;
   for(int k = 0; k < w; k++) {
      int    j  = (last - k + ND_MAXW) % ND_MAXW;
      double t  = (double)(sb.sec[j] - s0), y = sb.px[j] - p0, t2 = t * t;
      S0 += 1.0; S1 += t; S2 += t2; S3 += t2 * t; S4 += t2 * t2;
      Y0 += y;   Y1 += t * y; Y2 += t2 * y; YY += y * y;
   }
   double det = S0 * (S2 * S4 - S3 * S3) - S1 * (S1 * S4 - S2 * S3) + S2 * (S1 * S3 - S2 * S2);
   if(MathAbs(det) < 1.0e-9) return false;
   double a = (Y0 * (S2 * S4 - S3 * S3) - S1 * (Y1 * S4 - S3 * Y2) + S2 * (Y1 * S3 - S2 * Y2)) / det;
   double b = (S0 * (Y1 * S4 - S3 * Y2) - Y0 * (S1 * S4 - S2 * S3) + S2 * (S1 * Y2 - Y1 * S2)) / det;
   double c = (S0 * (S2 * Y2 - Y1 * S3) - S1 * (S1 * Y2 - Y1 * S2) + Y0 * (S1 * S3 - S2 * S2)) / det;
   double sst = YY - Y0 * Y0 / S0;
   if(sst <= 1.0e-12) return false;                      // ราคานิ่งทั้งหน้าต่าง
   double sse = MathMax(0.0, YY - a * Y0 - b * Y1 - c * Y2);
   f.sec0 = s0;
   f.b    = b;
   f.c    = c;
   f.r2   = 1.0 - sse / sst;
   f.vt   = (c != 0.0) ? -b / (2.0 * c) : 1.0e9;
   f.vpx  = (c != 0.0) ? p0 + a + b * f.vt + c * f.vt * f.vt : p0;
   f.ok   = true;
   return true;
}

// ฝั่ง dir มีโหนดใหม่ไหม (เรียกหลัง fit ทุกวินาที, watching = กำลังเฝ้าฝั่งนี้)
bool NodeCheck(NodeSide &ns, const NodeFit &f, int dir, bool watching, datetime bar) {
   if(ns.bar != bar) { ns.bar = bar; ns.count = 0; ns.armed = true; ns.v_msc = 0; ns.px = 0.0; }
   if(!f.ok) return false;
   double g = (dir == -1) ? 1.0 : -1.0;
   if(g * f.b > 0.0) { ns.armed = true; return false; }    // ยังวิ่งไปทางยอด → พร้อมจับโหนดถัดไป
   if(!watching || !ns.armed) return false;
   if(g * f.c >= 0.0) return false;                         // ต้องโค้งคว่ำ (SELL) / โค้งหงาย (BUY)
   if(f.vt > -(double)InpNodeMinPast_Sec || f.vt < -(double)(InpNodeWindow_Sec - 1)) return false;
   if(f.r2 < InpNodeMinR2) return false;
   ns.armed = false;
   ns.count++;
   ns.v_msc = (long)MathRound(((double)f.sec0 + f.vt) * 1000.0);
   ns.px    = f.vpx;
   return true;
}

// ค่าของโหนด + เทียบกับยอดของการเฝ้า (lower high = โหนดต่ำกว่ายอด) → เก็บลง ns ด้วย
bool NodeMake(NodeRec &r, NodeSide &ns, const NodeFit &f, int dir, const WatchState &w, const ZCache &zc) {
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(!ZAtPrice(zc, f.vpx, zr, zs, fit, sig, fl, mn, ssd) || ssd <= 0.0) return false;
   double g = (dir == -1) ? 1.0 : -1.0;
   r.v_msc = ns.v_msc;
   r.d_msc = (f.sec0 + 1) * 1000;
   r.dir   = dir;
   r.tier  = w.tier;
   r.seq   = ns.count;
   r.px    = f.vpx;
   r.zr    = zr;
   r.zs    = zs;
   r.d1    = g * f.b / ssd;
   r.d2    = g * 2.0 * f.c / ssd;
   r.r2    = f.r2;
   r.sd    = ssd;
   r.ext_hi = ZHi(dir, w.ext_r, w.ext_s);
   r.ext_px = w.ext_px;
   ns.zr = zr; ns.zs = zs; ns.ext_hi = r.ext_hi; ns.ext_px = r.ext_px;
   return true;
}

// ยอดที่ต่ำลง: Z สุดขั้วของการเฝ้า − Z ที่โหนด (+ = โหนดต่ำกว่ายอด) / ระยะราคา (จุด)
double NodeLowerHighZ(int dir, double ext_hi, double zr, double zs) { return ext_hi - ZHi(dir, zr, zs); }
double NodeLowerHighPts(int dir, double ext_px, double px) { return PriceToPts((dir == -1) ? ext_px - px : px - ext_px); }

// โหนดผ่านเกณฑ์โหมด LH: ยอดที่สอง (โหนด) ต่ำกว่ายอดแรกของการเฝ้า ≥ InpLH_MinZ
bool NodeIsLH(const NodeRec &r) { return NodeLowerHighZ(r.dir, r.ext_hi, r.zr, r.zs) >= InpLH_MinZ; }

void NodeAppend(NodeRec &arr[], const NodeRec &r) {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1, 256);
   arr[n] = r;
}

// EA จริง: เรียกเมื่อมีวินาทีจบเพิ่ม (หลังอัปเดตการเฝ้า)
void LiveNodeStep(datetime bar) {
   NodeFitCalc(g_lv_sb, InpNodeWindow_Sec, g_lv_fit);
   NodeRec r;
   if(NodeCheck(g_lv_ns_s, g_lv_fit, -1, g_wsell.active, bar) && NodeMake(r, g_lv_ns_s, g_lv_fit, -1, g_wsell, g_zc)) {
      NodeAppend(g_nd_lv, r);
      g_lh_sig_s = NodeIsLH(r);
   }
   if(NodeCheck(g_lv_ns_b, g_lv_fit,  1, g_wbuy.active,  bar) && NodeMake(r, g_lv_ns_b, g_lv_fit,  1, g_wbuy,  g_zc)) {
      NodeAppend(g_nd_lv, r);
      g_lh_sig_b = NodeIsLH(r);
   }
}

// ข้อความโหนดล่าสุดของฝั่ง (Dashboard)
string NodeStatusText(const NodeSide &ns, datetime bar, long now_msc) {
   if(ns.bar != bar || ns.count <= 0) return "";
   return StringFormat(" | โหนด N%d @ %s (%.0f วิที่แล้ว)", ns.count, DoubleToString(ns.px, _Digits), (double)(now_msc - ns.v_msc) / 1000.0);
}

// อยู่ในช่วงห้ามเปิดไม้ต้นแท่งไหม (เวลาแท่งของ TF ของ Z ตรงกับเวลาเซิร์ฟเวอร์หารลงตัว)
bool InBarStartDelay(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   if(per <= 0) return false;
   return ((long)t % per) < (long)InpBarStartDelay_Sec;
}

// ห้ามเฝ้า / เปิดไม้ช่วงท้ายแท่ง (InpBarEndBlock_Sec วินาทีก่อนปิดแท่งของ TF ของ Z)
bool InBarEndBlock(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   if(per <= 0 || InpBarEndBlock_Sec <= 0) return false;
   return ((long)t % per) >= per - (long)InpBarEndBlock_Sec;
}

// ช่วงเวลาที่ห้ามเฝ้า / เปิดไม้ (ไม้ที่ถืออยู่ไม่เกี่ยว): นาทีแรก / ท้ายแท่ง / ข่าว High ± InpNewsBlock_Min
string TimeBlockReason(datetime t) {
   if(InBarStartDelay(t)) return "นาทีแรกของแท่ง";
   if(InBarEndBlock(t))   return "ท้ายแท่ง";
   if(NewsNear(t) >= 0)   return "ช่วงข่าว";
   return "";
}

// SL ทุกระดับ: High (SELL) / Low (BUY) ของแท่ง (TF ของ Z) ณ ตอนเปิดไม้ ± InpSLPeak_Pts
double SLPrice(int dir, double bar_hi, double bar_lo) {
   double d = PtsToPrice(InpSLPeak_Pts);
   return (dir == -1) ? bar_hi + d : bar_lo - d;
}

// ตัวกรองตอนยิง (ใช้ร่วมกัน) — เวลาตลาด + เพดานสเปรด
string EntryBlockReason(int ts, double bid, double ask) {
   if(ts != TS_OPEN) return "เวลาตลาด";
   double sp = PriceToPts(ask - bid);
   if(sp > InpMaxSpread_Pts) return StringFormat("สเปรด %.0f > %.0f จุด", sp, InpMaxSpread_Pts);
   return "";
}

bool TradeAllowed() {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
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

// เวลาเริ่มบังคับปิดของช่วงตลาดที่ครอบเวลา t (0 = ไม่มี)
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
// เปิด Market สวนกลับ: stage = ระดับวิกฤต (1-4) → Lot ตามระดับ, SL = High / Low ของแท่ง ณ ตอนนั้น ± InpSLPeak_Pts
//   คอมเมนต์ "<InpOrderComment> T3 X3.25 R+3.1 S+2.4" (X = Z สุดขั้วในทิศกระชาก) ใช้คืนค่ากฎในแท่งเมื่อรีสตาร์ท
bool OpenMarket(int dir, int stage, double bid, double ask, double ext_z, ulong &ticket) {
   double lot   = TierLot(stage);
   double price = (dir == -1) ? bid : ask;
   double hi    = MathMax(g_bar0_hi, bid);
   double lo    = (g_bar0_lo > 0.0) ? MathMin(g_bar0_lo, bid) : bid;
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double sl    = SLPrice(dir, hi, lo);
   if(dir == -1) sl = MathMax(sl, ask + stops + _Point);   // เคารพ Stops Level ของโบรก
   else          sl = MathMin(sl, bid - stops - _Point);
   sl = ND(sl);
   double tp    = ND(dir == -1 ? price - PtsToPrice(InpTP_Pts) : price + PtsToPrice(InpTP_Pts));
   string cmt   = StringFormat("%s %s X%.2f R%+.1f S%+.1f", InpOrderComment, StageTag(stage), ext_z, g_z_reg, g_z_sma);
   bool   ok    = (dir == -1) ? trade.Sell(lot, _Symbol, bid, sl, tp, cmt)
                              : trade.Buy (lot, _Symbol, ask, sl, tp, cmt);
   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      ticket = trade.ResultOrder();
      PrintFormat("✅ เปิด %s %s %.2f lot @ %s | SL %s (%s แท่ง %s ± %.0f จุด, ห่าง %.0f จุด) | Z_reg %+.2f / Z_SMA %+.2f (สุดขั้ว %.2f)",
                  StageTag(stage), (dir == -1 ? "SELL" : "BUY"), lot, DoubleToString(trade.ResultPrice(), _Digits),
                  DoubleToString(sl, _Digits), (dir == -1 ? "High" : "Low"), DoubleToString(dir == -1 ? hi : lo, _Digits),
                  InpSLPeak_Pts, PriceToPts(MathAbs(sl - price)),
                  g_z_reg, g_z_sma, ext_z);
      return true;
   }
   PrintFormat("❌ เปิด %s %s ไม่สำเร็จ: %u %s", StageTag(stage), (dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
   return false;
}

int OurPositionsTotal() {
   int b, s;
   CountPositions(b, s);
   return b + s;
}

//--------------------------------------------------------------------
// 🎯 ยิงไม้ + กฎในแท่ง (EA จริง)
//--------------------------------------------------------------------
// ครบเวลาเฝ้าของระดับ (T2 5 วิ / T3 2 วิ / T4 ทันที) → ตัวกรอง → สวนกลับ (ติดตัวกรอง = ทิ้งสัญญาณ)
void LiveFire(int dir, int ts, double bid, double ask) {
   WatchState w;
   if(dir == -1) w = g_wsell; else w = g_wbuy;
   string   side = (dir == -1) ? "SELL" : "BUY";
   int      tier = w.tier;
   datetime now  = ServerNow();

   string why = EntryBlockReason(ts, bid, ask);
   if(why == "" && !TradeAllowed()) why = "ปิด Algo Trading อยู่";
   if(why != "") {
      g_last_status = StringFormat("เฝ้า %s %s ครบเวลาแล้ว แต่ติด: %s → ทิ้งสัญญาณ", side, StageTag(tier), why);
      if(dir == -1) WatchReset(g_wsell); else WatchReset(g_wbuy);
      return;
   }
   if(now < g_next_try) return;

   ulong ticket = 0;
   if(OpenMarket(dir, tier, bid, ask, ZHi(dir, w.ext_r, w.ext_s), ticket)) {
      g_last_status = StringFormat("เปิดสวนกลับ %s %s (Lot %.2f, ลึกสุด T%d) | สุดขั้ว R %+.2f / S %+.2f → ตอนยิง R %+.2f / S %+.2f",
                                   side, StageTag(tier), TierLot(tier), w.max_tier, w.ext_r, w.ext_s, g_z_reg, g_z_sma);
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
   } else {
      g_next_try    = now + 1;   // กันยิงคำสั่งรัว ๆ เมื่อโบรกปฏิเสธ (ยังเฝ้าต่อ)
      g_last_status = side + " ส่งคำสั่งไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

// เรียกทุก Tick และทุก 1 วินาที — ครั้งละ 1 ไม้: ช่วงห้าม (นาทีแรก ท้ายแท่ง ข่าว) / ขึ้นแท่งใหม่ = ล้างการเฝ้า,
// มีไม้ถืออยู่ = เฝ้าต่อแต่ยังไม่ยิง
void LiveSignalStep(long now_msc, int ts, double bid, double ask, bool update_watch) {
   if(!g_z_valid) return;
   bool     sec_done = SecFeed(g_lv_sb, now_msc, bid);
   datetime now_t   = (datetime)(now_msc / 1000);
   bool     busy    = OurPositionsTotal() > 0;
   bool     blocked = (TimeBlockReason(now_t) != "");
   datetime bar     = BarStartOf(now_t);
   GateSync(g_gs, bar);
   GateSync(g_gb, bar);

   if(blocked || g_bar_changed) {
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
      g_bar_changed = false;
      if(blocked) return;
   }
   if(update_watch) {
      WatchUpdate(g_wsell, -1, g_z_reg, g_z_sma, now_msc, bid, ask, ZFloat(-1, g_bar0_fz), g_gs);
      WatchUpdate(g_wbuy,   1, g_z_reg, g_z_sma, now_msc, bid, ask, ZFloat( 1, g_bar0_fz), g_gb);
   }
   if(sec_done) LiveNodeStep(bar);
   bool lh_s = g_lh_sig_s, lh_b = g_lh_sig_b;   // สัญญาณโหนด LH ใช้ได้เฉพาะวินาทีที่ยืนยัน
   g_lh_sig_s = false;
   g_lh_sig_b = false;
   if(busy) return;
   if(g_lh_on) {   // โหมด LH: ยิงตอนยืนยันโหนดที่ต่ำกว่ายอด (ไม่ใช้ตัวจับเวลา)
      if(lh_s && g_wsell.active)     LiveFire(-1, ts, bid, ask);
      else if(lh_b && g_wbuy.active) LiveFire( 1, ts, bid, ask);
      return;
   }
   if(WatchReady(g_wsell, now_msc))     LiveFire(-1, ts, bid, ask);
   else if(WatchReady(g_wbuy, now_msc)) LiveFire( 1, ts, bid, ask);
}

// ระดับ (T1-T4) จากคอมเมนต์ของดีลเปิด เช่น "7L-CNT T3 X3.25 R+3.1 S+2.4" (0 = อ่านไม่ได้)
int TierFromComment(string c) {
   for(int t = 4; t >= 1; t--)
      if(StringFind(c, " T" + IntegerToString(t) + " ") >= 0) return t;
   return 0;
}

// Z สุดขั้ว (X) จากคอมเมนต์ (0 = ไม่มี)
double ExtZFromComment(string c) {
   int k = StringFind(c, " X");
   return (k >= 0) ? StringToDouble(StringSubstr(c, k + 2, 6)) : 0.0;
}

// ข้อมูลไม้จากดีลเปิดของโพซิชัน (เปลี่ยนรายการประวัติที่เลือกเป็นของโพซิชันนี้)
bool EntryInfoOfPosition(long pos_id, int &dir, int &tier, double &ext_z, datetime &t_in) {
   if(!HistorySelectByPosition(pos_id)) return false;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      string c = HistoryDealGetString(d, DEAL_COMMENT);
      dir   = (HistoryDealGetInteger(d, DEAL_TYPE) == DEAL_TYPE_SELL) ? -1 : 1;
      tier  = TierFromComment(c);
      ext_z = ExtZFromComment(c);
      t_in  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      return true;
   }
   return false;
}

bool IsOurDeal(ulong deal, long entry) {
   return (HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagic && HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol &&
           HistoryDealGetInteger(deal, DEAL_ENTRY) == entry);
}

// ดีลปิดไม้ของ EA (deal ต้องถูกเลือกใน history แล้ว) → โพซิชัน / ชน SL ขาดทุนไหม / เวลา
bool OutDealInfo(ulong deal, long &pos_id, bool &sl_loss, datetime &t) {
   if(!IsOurDeal(deal, DEAL_ENTRY_OUT)) return false;
   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   pos_id  = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   sl_loss = (HistoryDealGetInteger(deal, DEAL_REASON) == DEAL_REASON_SL && profit < 0.0);
   t       = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   return true;
}

// ไม้ของ EA ปิด → กฎในแท่งของฝั่งนั้น + ล้างการเฝ้าฝั่งเดียวกัน
void LiveOnClose(int dir, long pos, int tier, double ext_z, datetime t_in, datetime t_out, bool sl_loss, bool live) {
   bool changed;
   if(dir == -1) { changed = GateOnClose(g_gs, tier, ext_z, BarStartOf(t_out), sl_loss); WatchReset(g_wsell); }
   else          { changed = GateOnClose(g_gb, tier, ext_z, BarStartOf(t_out), sl_loss); WatchReset(g_wbuy); }
   if(!changed || !live) return;
   g_last_status = (tier >= 3) ? StringFormat("%s %s ชน SL → ไม้ T3 / T4 ใหม่ในแท่งนี้ต้อง Z > %.2f", (dir == -1 ? "SELL" : "BUY"), StageTag(tier), ext_z + InpReEntryZStep)
                               : StringFormat("%s %s ชน SL → ปิด T2 ฝั่งนี้ที่เหลือของแท่ง", (dir == -1 ? "SELL" : "BUY"), StageTag(tier));
   PrintFormat("✋ %s", g_last_status);
}

// เริ่ม EA: คืนค่ากฎในแท่งของแท่งปัจจุบันจากประวัติ (ระดับ / Z สุดขั้ว อ่านจากคอมเมนต์ของดีลเปิด)
void RestoreGatesFromHistory() {
   datetime now = ServerNow();
   datetime bar = BarStartOf(now);
   GateSync(g_gs, bar);
   GateSync(g_gb, bar);
   if(!HistorySelect(bar - (datetime)DAY_SEC, now + 60)) return;
   int    total = HistoryDealsTotal();
   long   pos_ids[];
   int    pos_dir[], pos_tier[];
   double pos_x[];
   long   pos_t[];
   for(int i = 0; i < total; i++) {   // 1) ข้อมูลดีลเปิดทั้งหมด
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || !IsOurDeal(d, DEAL_ENTRY_IN)) continue;
      int n = ArraySize(pos_ids);
      ArrayResize(pos_ids, n + 1); ArrayResize(pos_dir, n + 1); ArrayResize(pos_tier, n + 1);
      ArrayResize(pos_x, n + 1);   ArrayResize(pos_t, n + 1);
      string c = HistoryDealGetString(d, DEAL_COMMENT);
      pos_ids[n]  = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      pos_dir[n]  = (HistoryDealGetInteger(d, DEAL_TYPE) == DEAL_TYPE_SELL) ? -1 : 1;
      pos_tier[n] = TierFromComment(c);
      pos_x[n]    = ExtZFromComment(c);
      pos_t[n]    = HistoryDealGetInteger(d, DEAL_TIME);
   }
   for(int i = 0; i < total; i++) {   // 2) เล่นดีลของแท่งปัจจุบันตามลำดับเวลา
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (datetime)HistoryDealGetInteger(d, DEAL_TIME) < bar) continue;
      long pos = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      int  k   = -1;
      for(int q = ArraySize(pos_ids) - 1; q >= 0; q--) if(pos_ids[q] == pos) { k = q; break; }
      if(k < 0) continue;
      long     p;
      bool     sl_loss;
      datetime t;
      if(OutDealInfo(d, p, sl_loss, t))
         LiveOnClose(pos_dir[k], pos, pos_tier[k], pos_x[k], (datetime)pos_t[k], t, sl_loss, false);
   }
   if(g_gs.t2_block || g_gb.t2_block || g_gs.re_z > 0.0 || g_gb.re_z > 0.0)
      PrintFormat("ℹ️ คืนค่ากฎในแท่งจากประวัติ: SELL %s / BUY %s", GateText(g_gs), GateText(g_gb));
}

// สถานะกฎในแท่งแบบอ่านง่าย
string GateText(const SideGate &g) {
   string s = "";
   if(g.t2_block) s += "T2 ปิด";
   if(g.re_z > 0.0) s += (s == "" ? "" : ", ") + StringFormat("T3/T4 ต้อง Z > %.2f", g.re_z + InpReEntryZStep);
   return (s == "") ? "ปกติ" : s;
}

void CloseAllPositions() {
   WatchReset(g_wsell);
   WatchReset(g_wbuy);
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
   PrunePeaks();

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
         if(PeakUpdate(ticket, prof) >= start) {
            // กำไร (สูงสุดตั้งแต่เปิด) ถึงจุดเริ่มไล่จี้ → เปิดระบบไล่จี้ทันที (ไม่รอรอบ 5 วินาที)
            MarkActivated(ticket);
            PrintFormat("🔥 #%I64u เริ่มไล่จี้ (กำไร %.0f จุด หลังเปิด %d วินาที)", ticket, PriceToPts(prof), (int)(now - opened));
            TrailPosition(ticket, is_buy, sl, tp, bid, ask, dist, stops, freeze);
         }
         else if(InpQuickWindow_Sec > 0 && now - opened >= InpQuickWindow_Sec) {
            // ครบเวลาแล้วไม่ดีดกลับ → ตัดจบ
            if(trade.PositionClose(ticket)) {
               g_last_status = StringFormat("ตัดจบ #%I64u (ไม่ดีดกลับใน %d วินาที, %+.0f จุด)",
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

// ทุก Tick: อัปเดตกำไรสูงสุดของไม้ + กฎคืนกำไร (ยังไม่ถึงโล่ และกำไรคืนเกิน InpGiveback_Pct% จากจุดสูงสุด → ตัดจบ)
void GivebackStep(double bid, double ask) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      bool   is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double prof   = is_buy ? (bid - open) : (open - ask);
      double peak   = PeakUpdate(ticket, prof);
      bool   locked = (sl > 0.0) && (is_buy ? (sl > open) : (sl < open));
      if(locked || IsActivated(ticket) || !GivebackHit(peak, prof)) continue;
      if(ServerNow() < g_gb_retry) continue;
      if(trade.PositionClose(ticket)) {
         g_last_status = StringFormat("ตัดจบ #%I64u (คืนกำไร: สูงสุด %.0f → เหลือ %.0f จุด, คืนเกิน %.0f%%)",
                                      ticket, PriceToPts(peak), PriceToPts(prof), InpGiveback_Pct);
         PrintFormat("↩️ %s", g_last_status);
      } else {
         g_gb_retry = ServerNow() + 1;
         PrintFormat("❌ ตัดจบ (คืนกำไร) #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

//====================================================================
// 📈 7 LINES ENGINE (ย้ายมาจาก Indicator v8.82 — คำนวณบน TF ของกราฟ)
//====================================================================
color                 g_line_clr[7];   // ตั้งจาก Input ใน OnInit
const int             LINE_WIDTH[7] = {3, 1, 1, 2, 2, 1, 1};
const ENUM_LINE_STYLE LINE_STYLE[7] = {STYLE_SOLID, STYLE_SOLID, STYLE_SOLID, STYLE_SOLID, STYLE_SOLID, STYLE_DOT, STYLE_DOT};
const string          LINE_LABEL[7] = {"Main (SMA)", "L1 (EMA)", "L2 (LWMA)", "L3 (HMA)", "L4 (LSMA)", "L5 (ALMA)", "L6 (Kinematic)"};

void InitALMAWeights(int period) {
   ArrayResize(g_alma_w, period);
   g_alma_wsum = 0.0;
   double m = 0.85 * (period - 1);
   double s = period / 6.0;
   for(int k = 0; k < period; k++) {
      double x = (period - 1 - k);
      double w = MathExp(-MathPow(x - m, 2) / (2.0 * s * s));
      g_alma_w[k]  = w;
      g_alma_wsum += w;
   }
}

double LnSMA(const double &p[], int i, int period) {
   double sum = 0.0;
   for(int k = 0; k < period; k++) sum += p[i - k];
   return sum / period;
}

double LnWMA(const double &p[], int i, int period) {
   double sum = 0.0, wsum = 0.0;
   for(int k = 0; k < period; k++) {
      double w = (double)(period - k);
      sum += p[i - k] * w; wsum += w;
   }
   return (wsum > 0.0) ? sum / wsum : p[i];
}

double LnHMA(const double &p[], int i, int period) {
   int half_p = (int)MathMax(1, MathFloor(period / 2.0));
   int sqrt_p = (int)MathMax(1, MathFloor(MathSqrt(period)));
   double sum = 0.0, wsum = 0.0;
   for(int k = 0; k < sqrt_p; k++) {
      double diff = 2.0 * LnWMA(p, i - k, half_p) - LnWMA(p, i - k, period);
      double w    = (double)(sqrt_p - k);
      sum += diff * w; wsum += w;
   }
   return (wsum > 0.0) ? sum / wsum : p[i];
}

double LnLSMA(const double &p[], int i, int period) {
   double sx = 0.0, sy = 0.0, sxy = 0.0, sx2 = 0.0;
   for(int k = 0; k < period; k++) {
      double x = (double)(period - k), y = p[i - k];
      sx += x; sy += y; sxy += x * y; sx2 += x * x;
   }
   double denom = period * sx2 - sx * sx;
   if(denom == 0.0) return p[i];
   double m = (period * sxy - sx * sy) / denom;
   double b = (sy - m * sx) / period;
   return m * period + b;
}

double LnALMA(const double &p[], int i, int period) {
   if(g_alma_wsum <= 0.0) return p[i];
   double sum = 0.0;
   for(int k = 0; k < period; k++) sum += p[i - k] * g_alma_w[k];
   return sum / g_alma_wsum;
}

double LnKinematic(const double &p[], int i) {
   double p0 = (p[i]     + p[i - 1] + p[i - 2]) / 3.0;
   double p1 = (p[i - 1] + p[i - 2] + p[i - 3]) / 3.0;
   double p2 = (p[i - 2] + p[i - 3] + p[i - 4]) / 3.0;
   double vel = p0 - p1;
   return p0 + vel + (vel - (p1 - p2));
}

void ComputeLinesAt(int i) {
   double alpha = 2.0 / (InpFastPeriod + 1.0);
   g_lv[i][1] = (i == 0) ? g_lc[0] : g_lc[i] * alpha + g_lv[i - 1][1] * (1.0 - alpha);   // EMA ต่อเนื่องจากต้นหน้าต่าง
   if(i < g_lines_warm) return;
   g_lv[i][0] = LnSMA(g_lc, i, InpZ_Period);
   g_lv[i][2] = LnWMA(g_lc, i, InpFastPeriod);
   g_lv[i][3] = LnHMA(g_lc, i, InpFastPeriod);
   g_lv[i][4] = LnLSMA(g_lc, i, InpFastPeriod);
   g_lv[i][5] = LnALMA(g_lc, i, InpFastPeriod);
   g_lv[i][6] = LnKinematic(g_lc, i);
}

int g_lines_fail = 0;
int g_lines_err  = 0;

void SetLinesStatus(string st) {
   if(st == g_lines_status) return;
   g_lines_status = st;
   Print("📈 เส้น 7 เส้น: ", st);
}

datetime g_seg_times[];   // เวลาแท่งปลายของช่วงเส้นที่วาดอยู่ (เก่า→ใหม่)

string SegName(int L, datetime t) {
   return OBJ_PREFIX + "L" + IntegerToString(L) + "_" + IntegerToString((long)t);
}

// ช่วงเส้นของเส้น L ที่จบที่แท่ง i1 (ตั้งชื่อตามเวลาแท่ง → ไม่ต้องขยับทั้งชุดเมื่อขึ้นแท่งใหม่)
void SetLineSegment(int L, int i1) {
   if(L == 0 ? !InpShowLineMain : !InpShowLineFast) return;
   int i0 = i1 - 1;
   string name = SegName(L, g_lt[i1]);
   if(ObjectFind(0, name) < 0) {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, g_lt[i0], g_lv[i0][L], g_lt[i1], g_lv[i1][L])) {
         g_lines_fail++;
         g_lines_err = GetLastError();
         return;
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, g_line_clr[L]);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, LINE_WIDTH[L]);
      ObjectSetInteger(0, name, OBJPROP_STYLE, LINE_STYLE[L]);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);   // วาดทับแท่งเทียนเหมือนเส้น Indicator
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  name, OBJPROP_TOOLTIP, LINE_LABEL[L]);
      return;
   }
   ObjectMove(0, name, 0, g_lt[i0], g_lv[i0][L]);
   ObjectMove(0, name, 1, g_lt[i1], g_lv[i1][L]);
}

void SetBarSegments(int i1) {
   for(int L = 0; L < 7; L++) SetLineSegment(L, i1);
   int n = ArraySize(g_seg_times);
   if(n == 0 || g_seg_times[n - 1] < g_lt[i1]) {
      ArrayResize(g_seg_times, n + 1);
      g_seg_times[n] = g_lt[i1];
   }
}

// ลบช่วงเส้นที่หลุดหน้าต่าง InpLinesBars
void PruneSegments(datetime oldest_end) {
   int n = ArraySize(g_seg_times), w = 0;
   for(int i = 0; i < n; i++) {
      if(g_seg_times[i] < oldest_end) {
         for(int L = 0; L < 7; L++) ObjectDelete(0, SegName(L, g_seg_times[i]));
         continue;
      }
      g_seg_times[w++] = g_seg_times[i];
   }
   if(w != n) ArrayResize(g_seg_times, w);
}

// คำนวณค่าเส้นใหม่ทั้งหน้าต่าง (เบา) แต่แตะ object เฉพาะช่วงที่เปลี่ยน:
//  ครั้งแรก = วาดทั้งหน้าต่าง, ขึ้นแท่งใหม่ = ช่วงของแท่งที่เพิ่งปิด + แท่งใหม่ แล้วลบช่วงที่เก่าเกิน
bool RebuildLines() {
   int sqrt_p   = (int)MathMax(1, MathFloor(MathSqrt(InpFastPeriod)));
   g_lines_warm = MathMax(InpZ_Period, InpFastPeriod + sqrt_p) + 5;
   int total    = InpLinesBars + g_lines_warm + 100;   // +100 แท่งให้ EMA นิ่งก่อนเริ่มวาด

   int got_c = CopyClose(_Symbol, PERIOD_CURRENT, 0, total, g_lc);
   int got_t = CopyTime (_Symbol, PERIOD_CURRENT, 0, total, g_lt);
   if(got_c != total || got_t != total) {
      SetLinesStatus(StringFormat("⏳ รอประวัติราคา (ได้ %d/%d แท่ง, error %d)", MathMin(got_c, got_t), total, GetLastError()));
      g_lines_total = 0;
      return false;
   }
   ArrayResize(g_lv, total);
   bool first = (g_lines_total == 0 || ArraySize(g_seg_times) == 0);
   datetime prev_bar = g_lines_bar;
   g_lines_total = total;

   for(int i = 0; i < total; i++) ComputeLinesAt(i);
   g_lines_fail = 0;

   int oldest_i1 = total - InpLinesBars + 1;
   for(int i1 = oldest_i1; i1 < total; i1++) {
      if(!first && g_lt[i1] < prev_bar) continue;   // ช่วงเก่าวาดไว้แล้ว ไม่ต้องแตะ
      SetBarSegments(i1);
   }
   PruneSegments(g_lt[oldest_i1]);

   g_lines_bar = g_lt[total - 1];
   if(g_lines_fail > 0)
      SetLinesStatus(StringFormat("⚠️ สร้างเส้นไม่สำเร็จ %d ช่วง (error %d)", g_lines_fail, g_lines_err));
   else
      SetLinesStatus(StringFormat("✅ วาดแล้ว %d แท่ง (%s)", InpLinesBars, EnumToString(Period())));
   ChartRedraw(0);
   return true;
}

// ระหว่างแท่ง: อัปเดตเฉพาะค่าแท่งปัจจุบันและช่วงเส้นสุดท้าย
void UpdateLinesLive() {
   if(!g_draw || !InpShow7Lines) return;
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t0 == 0) return;
   if(g_lines_total == 0 || t0 != g_lines_bar) { RebuildLines(); return; }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    i   = g_lines_total - 1;
   if(bid <= 0.0 || bid == g_lc[i]) return;
   g_lc[i] = bid;
   ComputeLinesAt(i);
   for(int L = 0; L < 7; L++) SetLineSegment(L, i);
}

//====================================================================
// 🏷️ ป้ายค่า Z บนแท่งที่ถึงเกณฑ์ (TF ของ Z)
//   Z ของแท่ง j ที่ราคา P = Regression Z จากราคาปิด n−1 แท่งก่อนหน้า + P เป็นจุดปัจจุบัน
//   (ตรงกับ Z สดที่ EA เห็นตอนราคาไปถึง P) → SELL ใช้ High, BUY ใช้ Low
//====================================================================
string   g_zl_names[];
datetime g_zl_times[];
datetime g_barz_bar = 0;   // แท่งปัจจุบัน (TF ของ Z) ตอนอัปเดตล่าสุด

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

void RememberBarZLabel(string name, datetime t) {
   for(int i = ArraySize(g_zl_names) - 1; i >= 0; i--)
      if(g_zl_names[i] == name) return;
   int n = ArraySize(g_zl_names);
   ArrayResize(g_zl_names, n + 1);
   ArrayResize(g_zl_times, n + 1);
   g_zl_names[n] = name;
   g_zl_times[n] = t;
}

// วาด/ลบป้าย Z ของแท่งเวลา t — zr/zs = Regression/SMA Z ที่ High [0] และ Low [1], fz = Z_float ของแท่ง (+ = เหนือ SMA)
void SetBarZLabels(datetime t, double hi, double lo, const double &zr[], const double &zs[], const bool &ok[], double fz) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)t);

   for(int side = 0; side < 2; side++) {
      string name = OBJ_PREFIX + (side == 0 ? "ZL_S_" : "ZL_B_") + ts;
      bool   hit_r, hit_s;
      if(side == 0) { hit_r = zr[0] > InpT2_Z;  hit_s = zs[0] > InpT2_Z; }
      else          { hit_r = zr[1] < -InpT2_Z; hit_s = zs[1] < -InpT2_Z; }
      bool show = ok[side] && (hit_r || hit_s);
      if(!show) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }

      int   tier       = TierOf(side == 0 ? -1 : 1, zr[side], zs[side], ZFloat(side == 0 ? -1 : 1, fz), g_gate_none);
      bool  hit_active = (tier >= 1);
      color clr = !hit_active ? InpClrBarZOther : (side == 0 ? InpClrBarZSell : InpClrBarZBuy);
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
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("R%+.2f | S%+.2f | S*%+.1f", zr[side], zs[side], ZStar(zs[side])));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s (Z* %+.2f ไม่มีเพดาน) | %s",
                                   TimeToString(t, TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                   zr[side], (hit_r ? " ✓" : ""), zs[side], (hit_s ? " ✓" : ""), ZStar(zs[side]),
                                   (hit_active ? "ถึงระดับ " + StageTag(tier) : "ถึงเกณฑ์ไม่ครบ")));
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
         SetBarZLabels(t[j], h[j], l[j], zr, zs, ok, (fok ? (o[j] - sma) / sd : 0.0));
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
      EvaluateClosedBars(1, 1);   // ค่าจริงของแท่งที่เพิ่งปิด (เขียนทับป้ายสดเดิม)
      PruneBarZLabels();
      g_barz_bar = t0;
   }

   // แท่งปัจจุบัน: ใช้แคช Z สด + High/Low ที่ติดตามไว้
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
   if(InpShowBarZ) SetBarZLabels(t0, g_bar0_hi, g_bar0_lo, zr, zs, ok, g_bar0_fz);
   SetBarFloatLabel(t0, g_bar0_hi, g_bar0_lo, g_bar0_open, g_bar0_fsma, g_bar0_fsd, InpFloatMarkLive);   // แท่งปัจจุบัน: ค่าตอนเปิดแท่ง (คงที่)
}

//====================================================================
// 📍 มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน (TF ของ Z)
//====================================================================
struct EntryMark {
   ulong    deal;
   datetime t;
   double   price;
   int      dir;      // -1 SELL / 1 BUY
   bool     closed_bar;    // แท่งปิดแล้ว ระยะห่างคงที่
   string   cmt;
};
EntryMark g_marks[];

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

   // 1. ลูกศรที่ราคาเปิดไม้
   string na = OBJ_PREFIX + "EN_A_" + ds;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, m.t, m.price);
      ObjectSetInteger(0, na, OBJPROP_COLOR, is_sell ? InpClrEntrySell : InpClrEntryBuy);
      ObjectSetInteger(0, na, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }

   // 2. เส้นประแนวตั้งจากราคาเปิดไม้ถึงปลายไส้
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

   // 3. ตัวเลขระยะห่าง
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
   int tier_m = TierFromComment(m.cmt);
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("   %s%s | %s | ห่างไส้ %.0f", (tier_m > 0 ? StageTag(tier_m) + " " : ""), (is_sell ? "S" : "B"),
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

// ทุก 1 วินาที: อัปเดตระยะห่างของมาร์กในแท่งที่ยังไม่ปิด + ลบมาร์กที่เก่าเกินช่วง (ตอนขึ้นแท่งใหม่)
datetime g_marks_bar = 0;
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
// 🧪 TICK REPLAY — เล่นซ้ำ tick จริงด้วยกติกาเดียวกับ EA
//   (T2 5 วิ / T3 2 วิ / T4 ทันที / นาทีแรก + ท้ายแท่ง / ข่าว / ครั้งละ 1 ไม้ / กฎในแท่ง / TP / SL ยอด / โล่ / คืนกำไร / ตัดเวลา / ปิดสุดสัปดาห์)
//====================================================================
#define RX_OPEN   0
#define RX_TP     1
#define RX_SL     2
#define RX_CUT    3
#define RX_TRAIL  4
#define RX_WEEK   5
#define RX_GIVE   6

struct RTrade {
   long     msc_in;
   int      dir;
   int      stage;         // ระดับวิกฤตที่ยิง (1-3)
   int      max_tier;      // ระดับลึกสุดระหว่างเฝ้า
   double   lot;
   double   p_in, sl, tp;
   double   zr, zs, ext_r, ext_s;
   double   mfe, mae;      // กำไรสูงสุด / ติดลบสูงสุดระหว่างถือ (ราคา)
   double   sl0;           // SL ตอนเปิดไม้ (ก่อนขยับโล่)
   double   peak;          // High (SELL) / Low (BUY) ของแท่ง ณ ตอนเปิดไม้ ที่ใช้วาง SL
   int      bar_seq;       // ไม้ลำดับที่เท่าไหร่ของแท่ง (ทุกฝั่ง)
   // ปัจจัย "ใช่ยอดหรือยัง" ณ ตอนยิง (ทิศของการกระชาก = ทิศตรงข้ามไม้สวน, ระยะเป็นจุด)
   bool     a_ok;  double a_brk, a_rng;   // A: ระยะฉีกจาก High / Low สุดขั้วของ 2 แท่งก่อน, ช่วงแท่งเฉลี่ย 20 แท่ง
   bool     b_ok;  double b_m1, b_m0;     // B: ระยะที่ราคาวิ่งไปทางกระชากใน 30 วิล่าสุด / 30 วิก่อนหน้า
   double   c_dzr, c_dzs;                 // C: Z ลดจากค่าสุดขั้วระหว่างเฝ้า (Regression / SMA)
   double   d_pull;                       // D: ราคาถอยจากยอดไส้ของแท่ง
   bool     e_ok;  double e_r15, e_r60;   // E: tick ต่อวินาที 15 วิล่าสุด / 60 วิก่อนหน้านั้น
   double   z_float, z_open, z_gap;       // แท่งลอยตัว / ราคาเปิด / เส้นถดถอย เทียบ SMA ÷ SD20 (+ = ทิศของการกระชาก)
   int      nd_cnt;                       // โหนด: จำนวนโหนดของฝั่งนี้ในแท่งก่อนเข้าไม้
   double   nd_sec, nd_pts, nd_dz;        // โหนดล่าสุด: กี่วินาทีที่แล้ว / จุดเข้าห่างโหนด (จุด, ÷ SD20; + = ถอยจากโหนดแล้ว)
   bool     nd_fit;  double nd_d1, nd_d2, nd_r2;   // fit ตอนเข้าไม้: d1 Z/วิ, d2 Z/วิ² (+ = ทิศของการกระชาก), R²
   double   nd_zr, nd_zs;                 // Z ที่โหนดล่าสุด (ทิศของการกระชาก)
   double   nd_lh_dz, nd_lh_pts;          // โหนดล่าสุดต่ำกว่ายอดของการเฝ้า (ΔZ / จุด, + = ยอดที่ต่ำลง)
   // ติดตามต่อ InpPostTrack_Min นาทีหลังเข้าไม้ (แม้ไม้ปิดแล้ว): Z_SMA สูงสุด (ทิศของการกระชาก), ราคาสวน / ไปทางกำไรสูงสุด, เวลากลับถึง Z
   double   pt_zs_max, pt_adv, pt_fav, pt_back_sec;
   bool     pt_done;
   // ระยะกำไรระหว่างถือ (ราคา): ต่ำสุด = mae, สูงสุด = mfe, เฉลี่ยถ่วงตามเวลา = pa_sum / pa_ms
   double   pa_sum, pa_ms, pa_fav;
   long     pa_msc;
   bool     activated;
   long     last_trail_sec;
   datetime force_close;
   long     msc_out;
   double   p_out;
   int      reason;
   double   pnl;           // จุด
   double   usd;           // $ ตาม Lot
   bool     drawn_final;
};

struct RBlocked {
   long   msc;
   int    dir;
   double price;
   string why;
};

RTrade     g_rt[];
RBlocked   g_rb[];
int        g_rt_open      = -1;
int        g_rb_drawn     = 0;
SideGate   g_rp_gs;                  // กฎในแท่งของ Replay (SELL / BUY)
SideGate   g_rp_gb;

MqlRates   g_rr[];
int        g_rp_b         = -1;
datetime   g_rp_bar_t     = 0;
ZCache     g_rp_zc;
bool       g_rp_bar_chg   = false;
double     g_rp_hi        = 0.0;     // High / Low ของแท่งปัจจุบัน (จาก tick ที่เล่นมาแล้ว) สำหรับวาง SL
double     g_rp_lo        = 0.0;
WatchState g_rp_ws;
WatchState g_rp_wb;
long       g_tk_msc[];               // tick ย้อนหลัง ~2 นาที (Replay) สำหรับปัจจัย B / E
double     g_tk_bid[];
int        g_tk_head      = 0;
int        g_rp_csv_rows  = -1;      // จำนวนไม้ที่เขียนลง CSV ล่าสุด
double     g_rp_bid = 0.0, g_rp_ask = 0.0, g_rp_zr = 0.0, g_rp_zs = 0.0;
double     g_rp_sma = 0.0, g_rp_sd = 0.0, g_rp_ctr = 0.0;   // SMA / SD20 / เส้นถดถอย ณ tick ล่าสุด
double     g_rp_fz        = 0.0;     // Z_float ของแท่งที่กำลังเล่น (ราคาเปิด เทียบ SMA ตอนเปิดแท่ง, + = เหนือ SMA)
long       g_rp_msc       = 0;
bool       g_rp_have      = false;
bool       g_rp_init      = false;
bool       g_rp_caught    = false;
long       g_rp_cursor    = 0;
int        g_rp_retry     = 0;
int        g_rp_news_wait = 0;      // วินาทีที่รอปฏิทินข่าวก่อนเริ่มเล่นซ้ำ
long       g_rp_ticks     = 0;
string     g_rp_status    = "ยังไม่เริ่ม";
double     g_contract     = 100.0;
SecBuf     g_rp_sb;                  // โหนดของ Replay
NodeFit    g_rp_fit;
NodeSide   g_rp_ns_s, g_rp_ns_b;
NodeRec    g_nd_rp[];
int        g_nd_rp_drawn  = 0;
int        g_pt_from      = 0;       // ไม้แรกที่ยังติดตามต่ออยู่
bool       g_rp_lh_s      = false;   // Replay: เพิ่งยืนยันโหนด LH ฝั่ง SELL / BUY
bool       g_rp_lh_b      = false;
int        g_rp_csv_pt    = -1;      // จำนวนไม้ที่ติดตามครบตอนเขียน CSV ล่าสุด

void ReplayReset() {
   ArrayResize(g_rt, 0);
   ArrayResize(g_rb, 0);
   ArrayResize(g_rr, 0);
   g_rt_open = -1; g_rb_drawn = 0;
   ZeroMemory(g_rp_gs); ZeroMemory(g_rp_gb);
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false; g_rp_bar_chg = false; g_rp_hi = 0.0; g_rp_lo = 0.0;
   WatchReset(g_rp_ws); WatchReset(g_rp_wb);
   ArrayResize(g_tk_msc, 0); ArrayResize(g_tk_bid, 0); g_tk_head = 0;
   g_rp_csv_rows = -1;
   g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_zr = 0.0; g_rp_zs = 0.0;
   g_rp_msc = 0; g_rp_have = false; g_rp_init = false; g_rp_caught = false;
   g_rp_cursor = 0; g_rp_retry = 0; g_rp_ticks = 0; g_rp_news_wait = 0;
   g_rp_status = "ยังไม่เริ่ม";
   SecReset(g_rp_sb);
   g_rp_fit.ok = false;
   ZeroMemory(g_rp_ns_s); ZeroMemory(g_rp_ns_b);
   ArrayResize(g_nd_rp, 0);
   g_nd_rp_drawn = 0;
   g_rp_lh_s     = false;
   g_rp_lh_b     = false;
   g_pt_from     = 0;
   g_rp_csv_pt   = -1;
}

// ติดตามต่อหลังเข้าไม้ (ไม่ขึ้นกับ SL / การปิดไม้): Z_SMA สูงสุดในทิศของการกระชาก, ราคาสวน / ไปทางกำไรสูงสุด, เวลากลับถึง Z
void ReplayPostTrack(long msc, double bid, double zs) {
   long span = (long)InpPostTrack_Min * 60000;
   int  n    = ArraySize(g_rt);
   for(int i = g_pt_from; i < n; i++) {
      if(!g_rt[i].pt_done && msc - g_rt[i].msc_in > span) g_rt[i].pt_done = true;
      if(g_rt[i].pt_done) { if(i == g_pt_from) g_pt_from++; continue; }
      double zd  = (g_rt[i].dir == -1) ? zs : -zs;
      double adv = (g_rt[i].dir == -1) ? bid - g_rt[i].p_in : g_rt[i].p_in - bid;
      if(zd > g_rt[i].pt_zs_max) g_rt[i].pt_zs_max = zd;
      if(adv > g_rt[i].pt_adv)   g_rt[i].pt_adv    = adv;
      if(-adv > g_rt[i].pt_fav)  g_rt[i].pt_fav    = -adv;
      if(g_rt[i].pt_back_sec < 0.0 && zd <= InpPostBackZ) g_rt[i].pt_back_sec = (double)(msc - g_rt[i].msc_in) / 1000.0;
   }
}

bool ReplayLoadRates() {
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int count   = (InpReplayDays + 4) * per_day + InpZ_Period + 10;
   int got = CopyRates(_Symbol, InpZ_Timeframe, 0, count, g_rr);
   return (got > InpZ_Period + 3);
}

// เข้าแท่งใหม่ (TF ของ Z): สร้างแคช Z
void ReplayEnterBar(int b) {
   g_rp_b = b;
   if(g_rr[b].time == g_rp_bar_t) return;
   bool had   = (g_rp_bar_t != 0);
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
   }
   double fsma, fsd;
   g_rp_fz = FloatAtOpen(g_rp_zc, g_rr[b].open, fsma, fsd);
   if(had) g_rp_bar_chg = true;
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

int ReplayOpen(int dir, int stage, long msc, double price) {
   int i = ArraySize(g_rt);
   ArrayResize(g_rt, i + 1);
   double tp_d = PtsToPrice(InpTP_Pts);
   double hi   = (g_rp_hi > 0.0) ? MathMax(g_rp_hi, g_rp_bid) : g_rp_bid;
   double lo   = (g_rp_lo > 0.0) ? MathMin(g_rp_lo, g_rp_bid) : g_rp_bid;
   datetime bar = BarStartOf((datetime)(msc / 1000));
   int      seq = 1;
   for(int k = i - 1; k >= 0 && BarStartOf((datetime)(g_rt[k].msc_in / 1000)) == bar; k--) seq++;
   g_rt[i].msc_in   = msc;
   g_rt[i].dir      = dir;
   g_rt[i].stage    = stage;
   g_rt[i].lot      = TierLot(stage);
   g_rt[i].max_tier = stage;
   g_rt[i].p_in     = price;
   g_rt[i].sl       = SLPrice(dir, hi, lo);
   g_rt[i].peak     = (dir == -1) ? hi : lo;
   g_rt[i].bar_seq  = seq;
   g_rt[i].tp       = (dir == -1) ? price - tp_d : price + tp_d;
   g_rt[i].zr       = g_rp_zr;
   g_rt[i].zs       = g_rp_zs;
   g_rt[i].ext_r    = 0.0;
   g_rt[i].ext_s    = 0.0;
   g_rt[i].mfe = 0.0; g_rt[i].mae = 0.0;
   g_rt[i].sl0      = g_rt[i].sl;
   g_rt[i].a_ok = false; g_rt[i].a_brk = 0.0; g_rt[i].a_rng = 0.0;
   g_rt[i].b_ok = false; g_rt[i].b_m1 = 0.0; g_rt[i].b_m0 = 0.0;
   g_rt[i].c_dzr = 0.0; g_rt[i].c_dzs = 0.0; g_rt[i].d_pull = 0.0;
   g_rt[i].e_ok = false; g_rt[i].e_r15 = 0.0; g_rt[i].e_r60 = 0.0;
   g_rt[i].z_float = 0.0; g_rt[i].z_open = 0.0; g_rt[i].z_gap = 0.0;
   g_rt[i].nd_cnt = 0; g_rt[i].nd_sec = 0.0; g_rt[i].nd_pts = 0.0; g_rt[i].nd_dz = 0.0;
   g_rt[i].nd_fit = false; g_rt[i].nd_d1 = 0.0; g_rt[i].nd_d2 = 0.0; g_rt[i].nd_r2 = 0.0;
   g_rt[i].nd_zr = 0.0; g_rt[i].nd_zs = 0.0; g_rt[i].nd_lh_dz = 0.0; g_rt[i].nd_lh_pts = 0.0;
   g_rt[i].pt_zs_max = (dir == -1) ? g_rp_zs : -g_rp_zs;
   g_rt[i].pt_adv = 0.0; g_rt[i].pt_fav = 0.0; g_rt[i].pt_back_sec = -1.0; g_rt[i].pt_done = false;
   g_rt[i].pa_sum = 0.0; g_rt[i].pa_ms = 0.0; g_rt[i].pa_fav = 0.0; g_rt[i].pa_msc = msc;
   g_rt[i].activated      = false;
   g_rt[i].last_trail_sec = 0;
   g_rt[i].force_close    = ForceCloseTimeAt((datetime)(msc / 1000));
   g_rt[i].msc_out  = 0;
   g_rt[i].p_out    = 0.0;
   g_rt[i].reason   = RX_OPEN;
   g_rt[i].pnl      = 0.0;
   g_rt[i].usd      = 0.0;
   g_rt[i].drawn_final = false;
   g_rt_open = i;
   WatchReset(g_rp_ws);
   WatchReset(g_rp_wb);
   return i;
}

// ปิดไม้จำลอง + กฎในแท่งของแท่งที่ปิด (T2 ชน SL → ปิด T2, T3 / T4 ชน SL → ไม้ใหม่ต้อง Z สูงกว่า) + ล้างการเฝ้าฝั่งเดียวกัน
void ReplayClose(long msc_out, double price, int reason) {
   int i = g_rt_open;
   if(i < 0) return;
   g_rt[i].msc_out = msc_out;
   g_rt[i].p_out   = price;
   g_rt[i].reason  = reason;
   double diff     = (g_rt[i].dir == -1) ? (g_rt[i].p_in - price) : (price - g_rt[i].p_in);
   g_rt[i].pnl     = PriceToPts(diff);
   g_rt[i].usd     = diff * g_rt[i].lot * g_contract;
   ProfitAvgAdd(i, msc_out, diff);
   g_rt_open = -1;
   bool     sl_loss = (reason == RX_SL && diff < 0.0);
   datetime b_out   = BarStartOf((datetime)(msc_out / 1000));
   double   ext_z   = ZHi(g_rt[i].dir, g_rt[i].ext_r, g_rt[i].ext_s);
   if(g_rt[i].dir == -1) { GateOnClose(g_rp_gs, g_rt[i].stage, ext_z, b_out, sl_loss); WatchReset(g_rp_ws); }
   else                  { GateOnClose(g_rp_gb, g_rt[i].stage, ext_z, b_out, sl_loss); WatchReset(g_rp_wb); }
}

void ReplayFire(int dir, long fire_msc) {
   WatchState w;
   if(dir == -1) w = g_rp_ws; else w = g_rp_wb;
   datetime t   = (datetime)(fire_msc / 1000);
   int      tier = w.tier;
   string   why = TimeBlockReason(t);
   if(why == "") why = EntryBlockReason(GetTimeStateAt(t), g_rp_bid, g_rp_ask);
   if(why != "") {
      int k = ArraySize(g_rb);
      ArrayResize(g_rb, k + 1);
      g_rb[k].msc = fire_msc; g_rb[k].dir = dir; g_rb[k].why = StageTag(tier) + ": " + why;
      g_rb[k].price = (dir == -1) ? g_rp_bid : g_rp_ask;
      if(dir == -1) WatchReset(g_rp_ws); else WatchReset(g_rp_wb);
      return;
   }
   int i = ReplayOpen(dir, tier, fire_msc, (dir == -1) ? g_rp_bid : g_rp_ask);
   g_rt[i].ext_r    = w.ext_r;
   g_rt[i].ext_s    = w.ext_s;
   g_rt[i].max_tier = w.max_tier;
   ReplaySignalFactors(i, w, dir);
   ReplayNodeFactors(i, dir);
}

// โหนด ณ ตอนยิง: จำนวนโหนดในแท่ง + ห่างโหนดล่าสุด + อนุพันธ์จาก fit ล่าสุด
void ReplayNodeFactors(int i, int dir) {
   NodeSide ns;
   if(dir == -1) ns = g_rp_ns_s; else ns = g_rp_ns_b;
   long   msc = g_rt[i].msc_in;
   double sd  = g_rp_sd;
   if(ns.bar == BarStartOf((datetime)(msc / 1000)) && ns.count > 0) {
      double d = (dir == -1) ? ns.px - g_rt[i].p_in : g_rt[i].p_in - ns.px;
      g_rt[i].nd_cnt = ns.count;
      g_rt[i].nd_sec = (double)(msc - ns.v_msc) / 1000.0;
      g_rt[i].nd_pts = PriceToPts(d);
      g_rt[i].nd_dz  = (sd > 0.0) ? d / sd : 0.0;
      double g = (dir == -1) ? 1.0 : -1.0;
      g_rt[i].nd_zr     = g * ns.zr;
      g_rt[i].nd_zs     = g * ns.zs;
      g_rt[i].nd_lh_dz  = NodeLowerHighZ(dir, ns.ext_hi, ns.zr, ns.zs);
      g_rt[i].nd_lh_pts = NodeLowerHighPts(dir, ns.ext_px, ns.px);
   }
   if(g_rp_fit.ok && sd > 0.0) {
      double g = (dir == -1) ? 1.0 : -1.0;
      g_rt[i].nd_fit = true;
      g_rt[i].nd_d1  = g * g_rp_fit.b / sd;
      g_rt[i].nd_d2  = g * 2.0 * g_rp_fit.c / sd;
      g_rt[i].nd_r2  = g_rp_fit.r2;
   }
}

// Replay: เรียกเมื่อมีวินาทีจบเพิ่ม (หลังอัปเดตการเฝ้า)
void ReplayNodeStep(datetime bar) {
   NodeFitCalc(g_rp_sb, InpNodeWindow_Sec, g_rp_fit);
   NodeRec r;
   if(NodeCheck(g_rp_ns_s, g_rp_fit, -1, g_rp_ws.active, bar) && NodeMake(r, g_rp_ns_s, g_rp_fit, -1, g_rp_ws, g_rp_zc)) {
      NodeAppend(g_nd_rp, r);
      g_rp_lh_s = NodeIsLH(r);
   }
   if(NodeCheck(g_rp_ns_b, g_rp_fit,  1, g_rp_wb.active, bar) && NodeMake(r, g_rp_ns_b, g_rp_fit,  1, g_rp_wb, g_rp_zc)) {
      NodeAppend(g_nd_rp, r);
      g_rp_lh_b = NodeIsLH(r);
   }
}

//--- tick ย้อนหลังของ Replay (เก็บ ~2 นาที) ---
void TickBufAdd(long msc, double bid) {
   int n = ArraySize(g_tk_msc);
   ArrayResize(g_tk_msc, n + 1, 4096);
   ArrayResize(g_tk_bid, n + 1, 4096);
   g_tk_msc[n] = msc;
   g_tk_bid[n] = bid;
   while(g_tk_head < n && g_tk_msc[g_tk_head] < msc - 120000) g_tk_head++;
   if(g_tk_head > 20000) {   // ย้ายส่วนที่ยังใช้มาไว้ต้นอาเรย์
      int m = n + 1 - g_tk_head;
      for(int q = 0; q < m; q++) { g_tk_msc[q] = g_tk_msc[g_tk_head + q]; g_tk_bid[q] = g_tk_bid[g_tk_head + q]; }
      ArrayResize(g_tk_msc, m, 4096);
      ArrayResize(g_tk_bid, m, 4096);
      g_tk_head = 0;
   }
}

// index ของ tick สุดท้ายที่เวลา ≤ t (−1 = ไม่มีข้อมูลย้อนไปถึง t)
int TickBufAt(long t) {
   int lo = g_tk_head, hi = ArraySize(g_tk_msc) - 1, ans = -1;
   while(lo <= hi) {
      int mid = (lo + hi) / 2;
      if(g_tk_msc[mid] <= t) { ans = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   return ans;
}

// ปัจจัย "ใช่ยอดหรือยัง" ณ ตอนยิง (สถานะของ tick ก่อนหน้า = ตอนยิง)
void ReplaySignalFactors(int i, const WatchState &w, int dir) {
   int    b  = g_rp_b;
   double sg = (dir == -1) ? 1.0 : -1.0;   // ทิศของการกระชาก: SELL สวนขาขึ้น / BUY สวนขาลง
   double hi = (g_rp_hi > 0.0) ? MathMax(g_rp_hi, g_rp_bid) : g_rp_bid;
   double lo = (g_rp_lo > 0.0) ? MathMin(g_rp_lo, g_rp_bid) : g_rp_bid;
   // A: ระยะฉีกออกจาก High / Low สุดขั้วของ 2 แท่งก่อน + ช่วงแท่งเฉลี่ย 20 แท่ง
   if(b >= 20) {
      double rng = 0.0;
      for(int k = b - 20; k < b; k++) rng += g_rr[k].high - g_rr[k].low;
      g_rt[i].a_rng = PriceToPts(rng / 20.0);
      g_rt[i].a_brk = (dir == -1) ? PriceToPts(hi - MathMax(g_rr[b - 1].high, g_rr[b - 2].high))
                                  : PriceToPts(MathMin(g_rr[b - 1].low, g_rr[b - 2].low) - lo);
      g_rt[i].a_ok  = true;
   }
   // แท่งลอยตัว / ราคาเปิด / เส้นถดถอย เทียบ SMA (SMA / SD ณ ตอนยิง)
   g_rt[i].z_float = ZFloat(dir, g_rp_fz);
   g_rt[i].z_open  = (b >= 0) ? ZFromSMA(dir, g_rr[b].open, g_rp_sma, g_rp_sd) : 0.0;
   g_rt[i].z_gap   = ZFromSMA(dir, g_rp_ctr, g_rp_sma, g_rp_sd);
   // D: ถอยจากยอดไส้ของแท่ง
   g_rt[i].d_pull = (dir == -1) ? PriceToPts(hi - g_rp_bid) : PriceToPts(g_rp_bid - lo);
   // C: Z ลดจากค่าสุดขั้วระหว่างเฝ้า
   g_rt[i].c_dzr = sg * (w.ext_r - g_rp_zr);
   g_rt[i].c_dzs = sg * (w.ext_s - g_rp_zs);
   // B: แรงส่ง 30 วิ / E: อัตรา tick (ต้องมี tick ย้อนไปถึง 60 / 75 วิ)
   long now = g_rp_msc;
   int  k0 = TickBufAt(now), k30 = TickBufAt(now - 30000), k60 = TickBufAt(now - 60000);
   if(k0 >= 0 && k30 >= 0 && k60 >= 0) {
      g_rt[i].b_m1 = sg * PriceToPts(g_tk_bid[k0]  - g_tk_bid[k30]);
      g_rt[i].b_m0 = sg * PriceToPts(g_tk_bid[k30] - g_tk_bid[k60]);
      g_rt[i].b_ok = true;
   }
   int k15 = TickBufAt(now - 15000), k75 = TickBufAt(now - 75000);
   if(k0 >= 0 && k15 >= 0 && k75 >= 0) {
      g_rt[i].e_r15 = (k0 - k15) / 15.0;
      g_rt[i].e_r60 = (k15 - k75) / 60.0;
      g_rt[i].e_ok  = true;
   }
}

// ระยะกำไรเฉลี่ยถ่วงตามเวลา: สะสม (กำไรช่วงก่อนหน้า × เวลาที่คงอยู่) แล้วจำค่าใหม่
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

// เหตุการณ์ตามเวลาระหว่าง tick ก่อนหน้า → tick นี้ (ราคายังเป็นของ tick ก่อนหน้า)
void ReplayTimeEvents(long msc) {
   if(!g_rp_have) return;
   if(g_rt_open >= 0) {
      int  i   = g_rt_open;
      long wk  = (g_rt[i].force_close > 0) ? (long)g_rt[i].force_close * 1000 : LONG_MAX;
      long cut = (InpQuickWindow_Sec > 0 && !g_rt[i].activated) ? g_rt[i].msc_in + (long)InpQuickWindow_Sec * 1000 : LONG_MAX;
      double px = (g_rt[i].dir == -1) ? g_rp_ask : g_rp_bid;
      if(wk <= cut && wk <= msc)       ReplayClose(wk,  px, RX_WEEK);
      else if(cut < wk && cut <= msc)  ReplayClose(cut, px, RX_CUT);
      return;
   }
   // ครบเวลาเฝ้า (ราคาของ tick ก่อนหน้า) → ยิง (โหมด LH ยิงตอนยืนยันโหนดแทน)
   if(g_lh_on) return;
   if(WatchReady(g_rp_ws, msc))      ReplayFire(-1, MathMax(WatchDeadline(g_rp_ws), g_rp_msc));
   else if(WatchReady(g_rp_wb, msc)) ReplayFire( 1, MathMax(WatchDeadline(g_rp_wb), g_rp_msc));
}

// ไม้ที่ถืออยู่: SL / TP / คืนกำไร / โล่ ด้วยราคา tick ปัจจุบัน// ไม้ที่ถืออยู่: SL / TP / โล่ ด้วยราคา tick ปัจจุบัน
void ReplayManageTick(long msc, double bid, double ask) {
   int i = g_rt_open;
   if(i < 0) return;
   int d = g_rt[i].dir;
   double fav = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
   if(fav > g_rt[i].mfe) g_rt[i].mfe = fav;
   if(fav < g_rt[i].mae) g_rt[i].mae = fav;
   ProfitAvgAdd(i, msc, fav);
   if(d == -1) {
      if(g_rt[i].sl > 0.0 && ask >= g_rt[i].sl) { ReplayClose(msc, ask, g_rt[i].activated ? RX_TRAIL : RX_SL); return; }
      if(g_rt[i].tp > 0.0 && ask <= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP); return; }
   } else {
      if(g_rt[i].sl > 0.0 && bid <= g_rt[i].sl) { ReplayClose(msc, bid, g_rt[i].activated ? RX_TRAIL : RX_SL); return; }
      if(g_rt[i].tp > 0.0 && bid >= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP); return; }
   }
   double prof = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
   if(!g_rt[i].activated && GivebackHit(g_rt[i].mfe, prof)) { ReplayClose(msc, (d == -1) ? ask : bid, RX_GIVE); return; }
   long   sec  = msc / 1000;
   bool   do_trail = false;
   if(!g_rt[i].activated) {
      if(prof >= PtsToPrice(InpTrailStart_Pts)) { g_rt[i].activated = true; do_trail = true; }
   }
   else if(sec - g_rt[i].last_trail_sec >= InpTrailInterval_Sec) do_trail = true;
   if(do_trail) {
      double dist = PtsToPrice(InpTrailDist_Pts);
      if(d == -1) { double nsl = ask + dist; if(g_rt[i].sl <= 0.0 || nsl < g_rt[i].sl) g_rt[i].sl = nsl; }
      else        { double nsl = bid - dist; if(nsl > g_rt[i].sl) g_rt[i].sl = nsl; }
      g_rt[i].last_trail_sec = sec;
   }
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);

   ReplayTimeEvents(msc);                 // A) เหตุการณ์ตามเวลาด้วยราคาเดิม (ตัดเวลา / ยิงหลังครบเวลาเฝ้า)
   // A2) วินาทีก่อนหน้าจบ → fit โหนด (ราคา / การเฝ้า / แคช Z ของ tick ก่อนหน้า) → โหมด LH ยิงด้วยราคาของ tick ก่อนหน้า
   if(SecFeed(g_rp_sb, msc, bid) && g_rp_have) {
      ReplayNodeStep(BarStartOf((datetime)(g_rp_msc / 1000)));
      if(g_lh_on && g_rt_open < 0) {
         if(g_rp_lh_s && g_rp_ws.active)      ReplayFire(-1, g_rp_msc);
         else if(g_rp_lh_b && g_rp_wb.active) ReplayFire( 1, g_rp_msc);
      }
      g_rp_lh_s = false;
      g_rp_lh_b = false;
   }
   if(!ReplayBarFor(t)) return;           // B) แท่งของ tick นี้
   if(g_rp_hi <= 0.0 || bid > g_rp_hi) g_rp_hi = bid;
   if(g_rp_lo <= 0.0 || bid < g_rp_lo) g_rp_lo = bid;

   double zr = 0.0, zs = 0.0, fit, sig, mn, ssd;
   bool   fl;
   bool   zok = ZAtPrice(g_rp_zc, bid, zr, zs, fit, sig, fl, mn, ssd);
   if(zok) { g_rp_zr = zr; g_rp_zs = zs; g_rp_sma = g_rp_zc.ref + mn; g_rp_sd = ssd; g_rp_ctr = g_rp_zc.ref + fit; }

   if(g_rt_open >= 0) ReplayManageTick(msc, bid, ask);   // C) ไม้ที่ถืออยู่
   if(zok) ReplayPostTrack(msc, bid, zs);                  //    ติดตามต่อหลังเข้าไม้

   // D) เฝ้าค่าสุดขั้ว: ช่วงห้าม (นาทีแรก / ท้ายแท่ง / ข่าว) / ขึ้นแท่งใหม่ = ล้างการเฝ้า, มีไม้ถืออยู่ = เฝ้าต่อ (ยิงหลังไม้ปิด)
   bool blocked = (TimeBlockReason(t) != "");
   GateSync(g_rp_gs, BarStartOf(t));
   GateSync(g_rp_gb, BarStartOf(t));
   if(blocked || !zok || g_rp_bar_chg) { WatchReset(g_rp_ws); WatchReset(g_rp_wb); }
   if(!blocked && zok) {
      WatchUpdate(g_rp_ws, -1, zr, zs, msc, bid, ask, ZFloat(-1, g_rp_fz), g_rp_gs);
      WatchUpdate(g_rp_wb,  1, zr, zs, msc, bid, ask, ZFloat( 1, g_rp_fz), g_rp_gb);
   }
   g_rp_bar_chg = false;

   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc;
   g_rp_have = true;
   g_rp_ticks++;
   TickBufAdd(msc, bid);
}

string ReplayReasonName(int r) {
   switch(r) {
      case RX_TP:    return "TP";
      case RX_SL:    return "SL";
      case RX_CUT:   return "ตัดเวลา";
      case RX_TRAIL: return "โล่";
      case RX_WEEK:  return "ปิดสัปดาห์";
      case RX_GIVE:  return "คืนกำไร";
   }
   return "ถืออยู่";
}

void DrawReplayTrade(int i) {
   datetime t_in    = (datetime)(g_rt[i].msc_in / 1000);
   bool     is_sell = (g_rt[i].dir == -1);
   string   id      = IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
   int      shift   = iBarShift(_Symbol, InpZ_Timeframe, t_in, false);
   double   hi = (shift >= 0) ? iHigh(_Symbol, InpZ_Timeframe, shift) : 0.0;
   double   lo = (shift >= 0) ? iLow (_Symbol, InpZ_Timeframe, shift) : 0.0;
   double   tip = is_sell ? hi : lo;
   double   gap = (tip > 0.0) ? PriceToPts(MathAbs(tip - g_rt[i].p_in)) : 0.0;
   bool     open = (g_rt[i].reason == RX_OPEN);
   color    clr  = is_sell ? InpClrSimSell : InpClrSimBuy;
   string   tag  = StageTag(g_rt[i].stage);

   string na = OBJ_PREFIX + "RP_A_" + id, ng = OBJ_PREFIX + "RP_G_" + id;
   string nl = OBJ_PREFIX + "RP_L_" + id, nt = OBJ_PREFIX + "RP_T_" + id;

   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, t_in, g_rt[i].p_in);
      ObjectSetInteger(0, na, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }
   if(tip > 0.0) {
      if(ObjectFind(0, ng) < 0) {
         ObjectCreate(0, ng, OBJ_TREND, 0, t_in, g_rt[i].p_in, t_in, tip);
         ObjectSetInteger(0, ng, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, ng, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, ng, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, ng, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, ng, OBJPROP_HIDDEN, true);
      }
      ObjectMove(0, ng, 1, t_in, tip);
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
      ObjectSetInteger(0, nl, OBJPROP_COLOR, (g_rt[i].pnl > 0.0) ? InpClrSimWin : InpClrSimLoss);
   }
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_in, g_rt[i].p_in);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, nt, OBJPROP_COLOR, open ? clr : ((g_rt[i].pnl > 0.0) ? InpClrSimWin : InpClrSimLoss));
   ObjectSetString(0, nt, OBJPROP_TEXT,
                   open ? StringFormat("%s %s %.2f | %s | ห่างไส้ %.0f | ถืออยู่   ", tag, (is_sell ? "S" : "B"), g_rt[i].lot, BarMinText(t_in), gap)
                        : StringFormat("%s %s %.2f | %s | ห่างไส้ %.0f | %s %+.0f ($%+.2f)   ", tag, (is_sell ? "S" : "B"), g_rt[i].lot,
                                       BarMinText(t_in), gap, ReplayReasonName(g_rt[i].reason), g_rt[i].pnl, g_rt[i].usd));

   string tipText = StringFormat("จำลอง %s %s %.2f lot @ %s (%s, %s ของแท่ง M15)\nZ ตอนเข้า R %+.2f / S %+.2f",
                                 tag, (is_sell ? "SELL" : "BUY"), g_rt[i].lot, DoubleToString(g_rt[i].p_in, _Digits),
                                 TimeToString(t_in, TIME_DATE|TIME_SECONDS), BarMinText(t_in), g_rt[i].zr, g_rt[i].zs);
   tipText += StringFormat(" | สุดขั้วระหว่างเฝ้า R %+.2f / S %+.2f | ลึกสุด T%d", g_rt[i].ext_r, g_rt[i].ext_s, g_rt[i].max_tier);
   tipText += StringFormat("\nห่างปลายไส้ %.0f จุด | SL ตอนเข้า %s (High/Low แท่ง %s ± %.0f จุด) | ไม้ที่ %d ของแท่ง", gap, DoubleToString(g_rt[i].sl0, _Digits),
                           DoubleToString(g_rt[i].peak, _Digits), InpSLPeak_Pts, g_rt[i].bar_seq);
   if(!open)
      tipText += StringFormat("\nออก %s @ %s (%s) | %+.0f จุด | $%+.2f | ถือ %d วินาที",
                              ReplayReasonName(g_rt[i].reason), DoubleToString(g_rt[i].p_out, _Digits),
                              TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS),
                              g_rt[i].pnl, g_rt[i].usd, (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000))
               + StringFormat("\nระยะกำไรระหว่างถือ: ต่ำสุด %+.0f / สูงสุด %+.0f / เฉลี่ย %+.0f จุด",
                              PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ProfitAvgPts(i));
   tipText += "\n" + SignalFactorText(i);
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tipText);
   if(tip > 0.0)  ObjectSetString(0, ng, OBJPROP_TOOLTIP, tipText);
   if(!open)      ObjectSetString(0, nl, OBJPROP_TOOLTIP, tipText);

   g_rt[i].drawn_final = (!open && shift > 0);
}

void DrawReplayBlocked(int k) {
   datetime t  = (datetime)(g_rb[k].msc / 1000);
   string   nx = OBJ_PREFIX + "RP_X_" + IntegerToString(g_rb[k].msc) + (g_rb[k].dir == -1 ? "_S" : "_B");
   if(ObjectFind(0, nx) < 0) {
      ObjectCreate(0, nx, OBJ_ARROW, 0, t, g_rb[k].price);
      ObjectSetInteger(0, nx, OBJPROP_ARROWCODE, 251);   // ×
      ObjectSetInteger(0, nx, OBJPROP_COLOR, InpClrSimBlocked);
      ObjectSetInteger(0, nx, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, nx, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nx, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nx, OBJPROP_TOOLTIP,
                   StringFormat("สัญญาณ %s ถูกทิ้ง %s @ %s\nเหตุผล: %s", (g_rb[k].dir == -1 ? "SELL" : "BUY"),
                                TimeToString(t, TIME_DATE|TIME_SECONDS), DoubleToString(g_rb[k].price, _Digits), g_rb[k].why));
}

// โหนด: จุด ● ที่ค่าของโหนด + ป้าย "N1 Z+3.12" ทางขวาของจุด (ชื่อป้าย = pfx + เวลา + ฝั่ง, จุด = ชื่อป้าย + "_D")
string NodeLabelName(const NodeRec &r, string pfx) { return pfx + IntegerToString(r.v_msc) + (r.dir == -1 ? "_S" : "_B"); }

void DrawNode(const NodeRec &r, string pfx) {
   datetime t   = (datetime)(r.v_msc / 1000);
   string   nt  = NodeLabelName(r, pfx), nd = nt + "_D";
   color    clr = (r.dir == -1) ? InpClrNodeSell : InpClrNodeBuy;
   double   z   = (r.dir == -1) ? MathMax(r.zr, r.zs) : MathMin(r.zr, r.zs);
   string   tip = StringFormat("โหนด N%d %s (%s) | กำลังเฝ้า %s\n%s (%s ของแท่ง) | ค่าของโหนด %s | Z_reg %+.2f / Z_SMA %+.2f",
                               r.seq, (r.dir == -1 ? "SELL" : "BUY"), (r.dir == -1 ? "ยอด: d1 = 0, d2 < 0" : "ก้น: d1 = 0, d2 > 0"), StageTag(r.tier),
                               TimeToString(t, TIME_DATE|TIME_SECONDS), BarMinText(t), DoubleToString(r.px, _Digits), r.zr, r.zs);
   tip += StringFormat("\nยืนยันหลังยอด %.0f วิ: d1 %+.3f Z/วิ | d2 %+.4f Z/วิ² (+ = ทิศของการกระชาก) | R² %.2f | SD20 %.0f จุด",
                       (double)(r.d_msc - r.v_msc) / 1000.0, r.d1, r.d2, r.r2, PriceToPts(r.sd));
   tip += StringFormat("\nZ* ที่โหนด %+.2f | ต่ำกว่ายอดของการเฝ้า ΔZ %+.2f / %+.0f จุด (+ = ยอดที่ต่ำลง)",
                       ZStar((r.dir == -1) ? r.zs : -r.zs), NodeLowerHighZ(r.dir, r.ext_hi, r.zr, r.zs), NodeLowerHighPts(r.dir, r.ext_px, r.px));
   if(ObjectFind(0, nd) < 0) {
      ObjectCreate(0, nd, OBJ_ARROW, 0, t, r.px);
      ObjectSetInteger(0, nd, OBJPROP_ARROWCODE, 159);   // ●
      ObjectSetInteger(0, nd, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, nd, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nd, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nd, OBJPROP_HIDDEN, true);
   }
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, t, r.px);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, nt, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("  N%d Z%+.2f", r.seq, z));
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tip);
   ObjectSetString(0, nd, OBJPROP_TOOLTIP, tip);
}

// โหนดของ EA จริง วาดเฉพาะเมื่อปิด Tick Replay (Replay เดินต่อแบบสดด้วยกติกาเดียวกันอยู่แล้ว → ไม่วาดซ้ำ)
void DrawLiveNodes() {
   if(!g_draw || !InpShowNodes || InpShowReplay) return;
   for(; g_nd_lv_drawn < ArraySize(g_nd_lv); g_nd_lv_drawn++) DrawNode(g_nd_lv[g_nd_lv_drawn], OBJ_PREFIX + "LN_");
}

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rt); i++)
      if(!g_rt[i].drawn_final) DrawReplayTrade(i);
   if(InpShowNodes)
      for(; g_nd_rp_drawn < ArraySize(g_nd_rp); g_nd_rp_drawn++) DrawNode(g_nd_rp[g_nd_rp_drawn], OBJ_PREFIX + "RP_N_");
   if(InpShowReplayBlocked)
      for(; g_rb_drawn < ArraySize(g_rb); g_rb_drawn++) DrawReplayBlocked(g_rb_drawn);
}

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n = 0, w = 0, c_tp = 0, c_sl = 0, c_cut = 0, c_tr = 0, c_wk = 0, c_gb = 0;
   int    cnt[5];
   double usd_st[5];
   ArrayInitialize(cnt, 0);
   ArrayInitialize(usd_st, 0.0);
   double usd = 0.0, peak = 0.0, dd = 0.0;
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      n++;
      if(g_rt[i].usd > 0.0) w++;
      usd += g_rt[i].usd;
      if(usd > peak) peak = usd;
      if(usd - peak < dd) dd = usd - peak;
      int st = MathMax(1, MathMin(4, g_rt[i].stage));
      cnt[st]++;
      usd_st[st] += g_rt[i].usd;
      switch(g_rt[i].reason) {
         case RX_TP: c_tp++; break;   case RX_SL: c_sl++; break;   case RX_CUT: c_cut++; break;
         case RX_TRAIL: c_tr++; break; case RX_WEEK: c_wk++; break; case RX_GIVE: c_gb++; break;
      }
   }
   string s = StringFormat("🧪 Replay %d วัน%s: %s\n   %d ไม้ | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | TP %d SL %d โล่ %d คืนกำไร %d ตัดเวลา %d ปิดสัปดาห์ %d | ถูกทิ้ง %d",
                           InpReplayDays, (g_lh_on ? " (โหมด LH)" : ""), g_rp_status, n, (n > 0 ? 100.0 * w / n : 0.0), usd, dd,
                           c_tp, c_sl, c_tr, c_gb, c_cut, c_wk, ArraySize(g_rb));
   string tail = "";
   if(g_rt_open >= 0) tail = " | มีไม้จำลองถืออยู่";
   s += StringFormat("\n   T2 %d ไม้ ($%+.2f) | T3 %d ไม้ ($%+.2f) | T4 %d ไม้ ($%+.2f)%s",
                     cnt[2], usd_st[2], cnt[3], usd_st[3], cnt[4], usd_st[4], tail);
   if(n > 0) {   // ระยะกำไรระหว่างถือ เฉลี่ยต่อไม้
      double s_min = 0.0, s_max = 0.0, s_avg = 0.0;
      for(int i = 0; i < ArraySize(g_rt); i++) {
         if(g_rt[i].reason == RX_OPEN) continue;
         s_min += PriceToPts(g_rt[i].mae);
         s_max += PriceToPts(g_rt[i].mfe);
         s_avg += ProfitAvgPts(i);
      }
      s += StringFormat("\n   ระยะกำไรระหว่างถือ (เฉลี่ยต่อไม้): ต่ำสุด %+.0f / สูงสุด %+.0f / เฉลี่ย %+.0f จุด", s_min / n, s_max / n, s_avg / n);
   }
   if(InpReplayCSV && g_rp_csv_rows >= 0)
      s += StringFormat("\n   📄 CSV: MQL5\\Files\\%s (%d ไม้)", ReplayCSVName(), g_rp_csv_rows);
   return s;
}

// ปัจจัยตอนยิงแบบอ่านง่าย (✓ = ผ่านเกณฑ์ที่ใช้แสดงผล: C Z ลด ≥ 0.3 / D ถอย ≥ 30% ของระยะฉีก)
string SignalFactorText(int i) {
   string s = StringFormat("Z_float %+.2f (ราคาเปิด vs SMA ตอนเปิดแท่ง) | Z_open %+.2f (vs SMA ตอนยิง) | Z_gap %+.2f (÷ SD20, + = ทิศกระชาก)\n",
                           g_rt[i].z_float, g_rt[i].z_open, g_rt[i].z_gap);
   s += g_rt[i].a_ok ? StringFormat("A ฉีก %+.0f จุด (%.2f× ช่วงแท่งเฉลี่ย %.0f)", g_rt[i].a_brk,
                                          (g_rt[i].a_rng > 0.0 ? g_rt[i].a_brk / g_rt[i].a_rng : 0.0), g_rt[i].a_rng)
                            : "A -";
   s += g_rt[i].b_ok ? StringFormat(" | B แรงส่ง 30 วิ %+.0f / ก่อนหน้า %+.0f", g_rt[i].b_m1, g_rt[i].b_m0) : " | B -";
   double dz = MathMin(g_rt[i].c_dzr, g_rt[i].c_dzs);
   s += StringFormat("\nC Z ลดจากยอด R %.2f / S %.2f%s", g_rt[i].c_dzr, g_rt[i].c_dzs, (dz >= 0.3 ? " ✓" : ""));
   double pf = (g_rt[i].a_ok && g_rt[i].a_brk > 0.0) ? g_rt[i].d_pull / g_rt[i].a_brk : 0.0;
   s += StringFormat(" | D ถอย %.0f จุด%s", g_rt[i].d_pull,
                     (g_rt[i].a_ok && g_rt[i].a_brk > 0.0 ? StringFormat(" (%.0f%% ของระยะฉีก%s)", 100.0 * pf, (pf >= 0.3 ? " ✓" : "")) : ""));
   s += g_rt[i].e_ok ? StringFormat(" | E tick %.1f/วิ เทียบ %.1f/วิ", g_rt[i].e_r15, g_rt[i].e_r60) : " | E -";
   s += (g_rt[i].nd_cnt > 0) ? StringFormat("\nโหนด %d จุดก่อนเข้า | ล่าสุด %.0f วิที่แล้ว | เข้าห่างโหนด %+.0f จุด (ΔZ %+.2f)",
                                             g_rt[i].nd_cnt, g_rt[i].nd_sec, g_rt[i].nd_pts, g_rt[i].nd_dz)
                             : "\nโหนด: ไม่มีก่อนเข้า";
   if(g_rt[i].nd_cnt > 0)
      s += StringFormat("\nโหนดล่าสุด: Z_reg %+.2f / Z_SMA %+.2f (Z* %+.2f) | ต่ำกว่ายอดของการเฝ้า ΔZ %+.2f / %+.0f จุด",
                        g_rt[i].nd_zr, g_rt[i].nd_zs, ZStar(g_rt[i].nd_zs), g_rt[i].nd_lh_dz, g_rt[i].nd_lh_pts);
   if(g_rt[i].pt_done)
      s += StringFormat("\nติดตาม %d นาทีหลังเข้า: Z_SMA สูงสุด %+.2f (Z* %+.2f) | สวนสูงสุด %.0f / ไปทางกำไรสูงสุด %.0f จุด | กลับถึง Z %.1f %s",
                        InpPostTrack_Min, g_rt[i].pt_zs_max, ZStar(g_rt[i].pt_zs_max), PriceToPts(g_rt[i].pt_adv), PriceToPts(g_rt[i].pt_fav), InpPostBackZ,
                        (g_rt[i].pt_back_sec >= 0.0 ? StringFormat("ใน %.0f วิ", g_rt[i].pt_back_sec) : "ไม่ถึง"));
   if(g_rt[i].nd_fit) s += StringFormat(" | ตอนเข้า d1 %+.3f Z/วิ, d2 %+.4f Z/วิ², R² %.2f", g_rt[i].nd_d1, g_rt[i].nd_d2, g_rt[i].nd_r2);
   return s;
}

string ReplayCSVName() { return "7LCEA_Replay_" + _Symbol + ".csv"; }

string ReplayReasonCode(int r) {
   switch(r) {
      case RX_TP:    return "TP";
      case RX_SL:    return "SL";
      case RX_CUT:   return "TIMECUT";
      case RX_TRAIL: return "TRAIL";
      case RX_WEEK:  return "WEEKCLOSE";
      case RX_GIVE:  return "GIVEBACK";
   }
   return "OPEN";
}

string CsvNum(bool ok, double v, int digits) { return ok ? DoubleToString(v, digits) : ""; }

// เขียนไม้จำลองที่ปิดแล้ว + ปัจจัยตอนยิง + ระยะกำไรระหว่างถือ (เขียนใหม่ทั้งไฟล์เมื่อมีไม้ปิดเพิ่ม)
void ReplayWriteCSV(int done, int pt_done) {
   string fn = ReplayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "time_in,side,tier,max_tier,bar_seq,lot,price_in,sl_peak,sl_init_pts,z_reg,z_sma,ext_zreg,ext_zsma,z_sma_star,ext_zsma_star,z_float,z_open,z_gap," +
                      "a_break_pts,a_avg_range_pts,a_break_ratio,b_move_last30_pts,b_move_prev30_pts," +
                      "c_zreg_drop,c_zsma_drop,d_pull_pts,d_pull_frac,e_ticks_per_sec_last15,e_ticks_per_sec_prev60," +
                      "node_count,node_sec_ago,node_dist_pts,node_dist_dz,fit_d1_zps,fit_d2_zps2,fit_r2," +
                      "node_zreg,node_zsma,node_zsma_star,node_lh_dz,node_lh_pts," +
                      "time_out,exit,hold_sec,pnl_pts,usd,profit_min_pts,profit_max_pts,profit_avg_pts," +
                      "post_min,post_max_zsma,post_max_zsma_star,post_max_adv_pts,post_max_fav_pts,post_back_z_sec\r\n");
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      string ln = StringFormat("%s,%s,%d,%d,%d,%.2f,%s,%s,%.0f,%.3f,%.3f,%.3f,%.3f,",
                               TimeToString((datetime)(g_rt[i].msc_in / 1000), TIME_DATE|TIME_SECONDS), (g_rt[i].dir == -1 ? "SELL" : "BUY"),
                               g_rt[i].stage, g_rt[i].max_tier, g_rt[i].bar_seq, g_rt[i].lot, DoubleToString(g_rt[i].p_in, _Digits),
                               DoubleToString(g_rt[i].peak, _Digits),
                               PriceToPts(MathAbs(g_rt[i].sl0 - g_rt[i].p_in)), g_rt[i].zr, g_rt[i].zs, g_rt[i].ext_r, g_rt[i].ext_s);
      double gz = (g_rt[i].dir == -1) ? 1.0 : -1.0;
      ln += StringFormat("%.3f,%.3f,", ZStar(gz * g_rt[i].zs), ZStar(gz * g_rt[i].ext_s));
      ln += StringFormat("%.3f,%.3f,%.3f,", g_rt[i].z_float, g_rt[i].z_open, g_rt[i].z_gap);
      bool af = g_rt[i].a_ok && g_rt[i].a_rng > 0.0;
      ln += CsvNum(g_rt[i].a_ok, g_rt[i].a_brk, 0) + "," + CsvNum(g_rt[i].a_ok, g_rt[i].a_rng, 0) + "," +
            CsvNum(af, (af ? g_rt[i].a_brk / g_rt[i].a_rng : 0.0), 3) + ",";
      ln += CsvNum(g_rt[i].b_ok, g_rt[i].b_m1, 0) + "," + CsvNum(g_rt[i].b_ok, g_rt[i].b_m0, 0) + ",";
      bool pf = g_rt[i].a_ok && g_rt[i].a_brk > 0.0;
      ln += StringFormat("%.3f,%.3f,%.0f,", g_rt[i].c_dzr, g_rt[i].c_dzs, g_rt[i].d_pull) +
            CsvNum(pf, (pf ? g_rt[i].d_pull / g_rt[i].a_brk : 0.0), 3) + ",";
      ln += CsvNum(g_rt[i].e_ok, g_rt[i].e_r15, 2) + "," + CsvNum(g_rt[i].e_ok, g_rt[i].e_r60, 2) + ",";
      bool nk = g_rt[i].nd_cnt > 0;
      ln += IntegerToString(g_rt[i].nd_cnt) + "," + CsvNum(nk, g_rt[i].nd_sec, 1) + "," + CsvNum(nk, g_rt[i].nd_pts, 0) + "," +
            CsvNum(nk, g_rt[i].nd_dz, 3) + "," + CsvNum(g_rt[i].nd_fit, g_rt[i].nd_d1, 4) + "," +
            CsvNum(g_rt[i].nd_fit, g_rt[i].nd_d2, 5) + "," + CsvNum(g_rt[i].nd_fit, g_rt[i].nd_r2, 3) + ",";
      ln += CsvNum(nk, g_rt[i].nd_zr, 3) + "," + CsvNum(nk, g_rt[i].nd_zs, 3) + "," + CsvNum(nk, ZStar(g_rt[i].nd_zs), 3) + "," +
            CsvNum(nk, g_rt[i].nd_lh_dz, 3) + "," + CsvNum(nk, g_rt[i].nd_lh_pts, 0) + ",";
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
   if(g_rp_csv_rows < 0) PrintFormat("📄 บันทึกไม้จำลอง %d ไม้ + ปัจจัยตอนยิง ลง MQL5\\Files\\%s (อัปเดตเมื่อมีไม้ปิดเพิ่ม)", done, fn);
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
   if(g_rp_caught) ReplayTimeEvents(now_msc);   // เวลาผ่านไปโดยไม่มี tick (ตัดเวลา / ยิงหลังครบเวลาเฝ้า)

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
// 📰 ข่าวบนกราฟ: เส้นเวลาข่าว + แถบแท่งข่าว (ย้อนหลังเท่าช่วงป้าย Z + 24 ชม.ข้างหน้า)
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

// สีป้าย Z ตามโซน: ถึง T2 = แดงส้ม/ฟ้า, ใกล้เกณฑ์ = ทอง, ปกติ = เงิน
color LiveZColor(double z) {
   if(z > InpT2_Z)                     return InpClrLiveSell;
   if(z < -InpT2_Z)                    return InpClrLiveBuy;
   if(z >= InpT2_Z - NEAR_ZONE ||
      z <= -InpT2_Z + NEAR_ZONE)       return InpClrLiveNear;
   return InpClrLiveNormal;
}

// ป้ายค่า Z สด: ติดขอบขวาของกราฟ ที่ความสูงเดียวกับราคา Bid (มองเห็นเสมอ ไม่ต้องเปิด Chart shift)
// อัปเดตเฉพาะเมื่อข้อความ/ตำแหน่งเปลี่ยน
void UpdateLiveZLabel(double bid) {
   if(!g_draw || !InpShowLiveZ) return;
   if(!g_z_valid) {
      if(ObjectFind(0, LABEL_LIVE_Z) >= 0) ObjectDelete(0, LABEL_LIVE_Z);
      g_live_z_text = "";
      return;
   }

   string text = StringFormat("R %+.2f | S %+.2f ▶", g_z_reg, g_z_sma);
   long now_msc = MathMax(g_last_tick_msc, (long)ServerNow() * 1000);
   if(g_wsell.active)      text = "SELL " + WatchShortText(g_wsell, now_msc) + "  |  " + text;
   else if(g_wbuy.active)  text = "BUY "  + WatchShortText(g_wbuy,  now_msc) + "  |  " + text;

   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, 0), bid, x, y)) return;
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(y < 8)     y = 8;          // ราคาหลุดขอบบน/ล่าง → ติดขอบไว้ให้ยังเห็น
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
                   StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s, Z* %+.2f) | T2 ทั้งคู่ > %.2f (ลอย ≤ %.1f) / T3 ตัวใด > %.2f / T4 ตัวใด > %.2f",
                                g_z_reg, DoubleToString(g_center, _Digits), g_z_sma, DoubleToString(g_sma_mean, _Digits), ZStar(g_z_sma),
                                InpT2_Z, InpT2EitherFloat, InpT3_Z, InpT4_Z));

   g_live_z_text = text;
   g_live_z_y    = y;
}

void UpdateZLines() {
   if(!g_draw || !g_z_valid) return;
   if(InpShowZLines) {
      MoveHLine(LINE_MAIN, g_center,                    InpClrZCenter,   STYLE_DOT,  1, "[Regression] เส้นกลาง Z = 0", g_line_main);
      MoveHLine(LINE_SELL, g_center + InpT2_Z * g_sigma, InpClrZSellLine, STYLE_DASH, 1, StringFormat("[Regression] SELL T2 Z > +%.2f", InpT2_Z), g_line_sell);
      MoveHLine(LINE_BUY,  g_center - InpT2_Z * g_sigma, InpClrZBuyLine,  STYLE_DASH, 1, StringFormat("[Regression] BUY T2 Z < −%.2f", InpT2_Z),  g_line_buy);
   }
   if(InpShowSmaZLines) {
      MoveHLine(LINE_SMA_MAIN, g_sma_mean,                     InpClrSmaCenter,   STYLE_DOT,     1, "[SMA20] เส้นกลาง Z = 0", g_line_sma_main);
      MoveHLine(LINE_SMA_SELL, g_sma_mean + InpT2_Z * g_sma_sd, InpClrSmaSellLine, STYLE_DASHDOT, 1, StringFormat("[SMA20] SELL T2 Z > +%.2f", InpT2_Z), g_line_sma_sell);
      MoveHLine(LINE_SMA_BUY,  g_sma_mean - InpT2_Z * g_sma_sd, InpClrSmaBuyLine,  STYLE_DASHDOT, 1, StringFormat("[SMA20] BUY T2 Z < −%.2f", InpT2_Z),  g_line_sma_buy);
   }
}

string WatchShortText(const WatchState &w, long now_msc) {
   double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
   if(left < 0.0) left = 0.0;
   if(g_lh_on) return StringFormat("เฝ้า %s รอโหนด LH", StageTag(w.tier));
   return StringFormat("เฝ้า %s ยิงใน %.1f วิ", StageTag(w.tier), left);
}

string WatchText(const WatchState &w, bool is_sell, long now_msc) {
   datetime t   = (datetime)(now_msc / 1000);
   string   sg  = is_sell ? "+" : "−";
   string blk = TimeBlockReason(t);
   if(blk != "")               return "⏳ ห้ามเฝ้า: " + blk;
   int      dir  = is_sell ? -1 : 1;
   double   zf   = ZFloat(dir, g_bar0_fz);
   SideGate g;
   if(is_sell) g = g_gs; else g = g_gb;
   string   gate = (g.bar == BarStartOf(t) && (g.t2_block || g.re_z > 0.0)) ? " | แท่งนี้: " + GateText(g) : "";
   string   hold = (OurPositionsTotal() > 0) ? " | ⏸️ มีไม้ถืออยู่ (ยิงหลังไม้ปิด)" : "";
   if(w.active) {
      double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
      if(left < 0.0) left = 0.0;
      string need = (w.tier >= 4) ? StringFormat("Z ตัวใด > %s%.2f, ยิงทันที", sg, InpT4_Z)
                  : (w.tier == 3) ? StringFormat("Z ตัวใด > %s%.2f, รอ %d วิ", sg, InpT3_Z, InpT3_Sec)
                  : StringFormat("Z %s > %s%.2f, รอ %d วิ", (zf > InpT2EitherFloat ? "ตัวใด (ลอย > " + DoubleToString(InpT2EitherFloat, 1) + ")" : "ทั้งคู่"),
                                 sg, InpT2_Z, InpT2_Sec);
      string fire = g_lh_on ? StringFormat("โหมด LH: ยิงเมื่อยืนยันโหนดที่ต่ำกว่ายอด ≥ %.2f Z", InpLH_MinZ)
                            : StringFormat("ไม่มี %s ใหม่มา %.1f วิ → ยิงในอีก %.1f วิ", (is_sell ? "High" : "Low"), (double)(now_msc - w.last_new) / 1000.0, left);
      return StringFormat("👀 เฝ้า %s (%s, Lot %.2f) | สุดขั้ว R %+.2f / S %+.2f | SL ถ้ายิงตอนนี้ %s | %s%s%s",
                          StageTag(w.tier), need, TierLot(w.tier), w.ext_r, w.ext_s,
                          DoubleToString(SLPrice(dir, g_bar0_hi, g_bar0_lo), _Digits), fire, hold, gate);
   }
   string t2  = !g_en[2] ? "T2 ปิดปุ่ม"
              : g.t2_block ? "T2 ปิดแท่งนี้"
              : (InpFloatFilter && zf <= InpFloatMin) ? StringFormat("T2 ปิด (ลอย %+.2f ≤ %.2f)", zf, InpFloatMin)
              : StringFormat("T2 Z %s > %s%.2f", (zf > InpT2EitherFloat ? "ตัวใด" : "ทั้งคู่"), sg, InpT2_Z);
   string t34 = (!g_en[3] && !g_en[4]) ? "T3/T4 ปิดปุ่ม"
              : (g.re_z > 0.0) ? StringFormat("T3/T4 ต้อง Z > %s%.2f", sg, g.re_z + InpReEntryZStep)
              : StringFormat("%s / %s", (g_en[3] ? StringFormat("T3 Z ตัวใด > %s%.2f", sg, InpT3_Z) : "T3 ปิดปุ่ม"),
                                        (g_en[4] ? StringFormat("T4 > %s%.2f", sg, InpT4_Z) : "T4 ปิดปุ่ม"));
   return StringFormat("✅ รอ %s | %s (Z_float %+.2f)%s", t2, t34, zf, hold);
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
      else {
         if(InpQuickWindow_Sec > 0) {
            long left = (long)InpQuickWindow_Sec - (long)(now - opened);
            if(left < 0) left = 0;
            st = StringFormat("⏱️ เหลือ %d วิ ต้องกำไรถึง %.0f", (int)left, InpTrailStart_Pts);
         }
         else
            st = StringFormat("รอกำไรถึง %.0f", InpTrailStart_Pts);
         double peak = PriceToPts(PeakOf(ticket));
         if(InpGiveback_Pct > 0.0)
            st += (peak >= InpGivebackMinPeak_Pts)
                  ? StringFormat(" | สูงสุด %.0f → ตัดถ้าเหลือ ≤ %.0f", peak, peak * (1.0 - InpGiveback_Pct / 100.0))
                  : StringFormat(" | สูงสุด %.0f", peak);
      }

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

   string z_str = g_z_valid
      ? StringFormat("Z_reg %+.2f (กลาง %s, σ %.0f จุด%s)  |  Z_SMA %+.2f (SMA20 %s, σ %.0f จุด) | Z* %+.2f (ไม่มีเพดาน) | ต่าง %+.2f",
                     g_z_reg, DoubleToString(g_center, _Digits), PriceToPts(g_sigma), (g_sigma_floor ? " พื้น" : ""),
                     g_z_sma, DoubleToString(g_sma_mean, _Digits), PriceToPts(g_sma_sd), ZStar(g_z_sma), g_z_reg - g_z_sma)
      : "รอข้อมูลแท่งเทียน...";
   string news_str = NextNewsText(now);

   long   now_msc = MathMax(g_last_tick_msc, (long)now * 1000);
   string msg = StringFormat("=== 📊 7-Lines Counter EA v12.90 (%s T2 ลอย>%.2f Z ทั้งคู่>%.1f %d วิ (ลอย>%.1f ตัวเดียวได้) | %s T3 Z ตัวใด>%.1f %d วิ | %s T4 >%.1f ทันที | SL High/Low แท่ง ± %.0f | คืนกำไร %.0f%%) ===\n",
                             (g_en[2] ? "✅" : "⛔"), InpFloatMin, InpT2_Z, InpT2_Sec, InpT2EitherFloat, (g_en[3] ? "✅" : "⛔"), InpT3_Z, InpT3_Sec,
                             (g_en[4] ? "✅" : "⛔"), InpT4_Z, InpSLPeak_Pts, InpGiveback_Pct);
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : R %+.2f / S %+.2f%s\n", g_prev_close_zr, g_prev_close_zs, (news_str == "" ? "" : " | " + news_str));
   if(g_z_valid)   // ÷ SD20, + = เหนือ SMA (ฝั่ง SELL ใช้ค่านี้ / ฝั่ง BUY ใช้ค่าลบ)
      msg += StringFormat("ระยะจาก SMA : Z_float %+.2f (ราคาเปิด %s vs SMA ตอนเปิดแท่ง %s) | Z_gap (ถดถอย − SMA) %+.2f\n",
                          g_bar0_fz, DoubleToString(g_bar0_open, _Digits), DoubleToString(g_bar0_fsma, _Digits),
                          ZFromSMA(-1, g_center, g_sma_mean, g_sma_sd));
   msg += "SELL : " + WatchText(g_wsell, true,  now_msc) + NodeStatusText(g_lv_ns_s, BarStartOf(now), now_msc) + "\n";
   msg += "BUY  : " + WatchText(g_wbuy,  false, now_msc) + NodeStatusText(g_lv_ns_b, BarStartOf(now), now_msc) + "\n";
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts);
   msg += StringFormat("กฎในแท่ง : SELL %s | BUY %s\n", (g_gs.bar == BarStartOf(now) ? GateText(g_gs) : "ปกติ"), (g_gb.bar == BarStartOf(now) ? GateText(g_gb) : "ปกติ"));
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
   if(InpShow7Lines) msg += "เส้น 7 เส้น : " + g_lines_status + "\n";
   msg += "สถานะล่าสุด : " + g_last_status;
   if(InpShowReplay) msg += "\n" + ReplayStatsText();
   msg += PositionLines(bid, ask, now);

   if(msg != g_last_comment) {
      g_last_comment = msg;
      Comment(msg);
   }
}

//====================================================================
// 🔘 ปุ่มเปิด/ปิด T2-T4 + ป้ายไม้ไม่ซ้อนกัน
//====================================================================
// เวลาภายในแท่ง (TF ของ Z) เช่น "น.07:32" = นาทีที่ 7 วินาทีที่ 32 นับจากเปิดแท่ง
string BarMinText(datetime t) {
   long sec = (long)t - (long)BarStartOf(t);
   return StringFormat("น.%02d:%02d", (int)(sec / 60), (int)(sec % 60));
}

const string BTN_PREFIX = "7LCEA_BTN_T";

string TierGVName(int tier) { return StringFormat("7LCEA_%s_%I64d_T%d", _Symbol, InpMagic, tier); }

// ค่าเริ่มต้นของปุ่ม: แก้ input = ใช้ input / เปลี่ยน TF, คอมไพล์ใหม่, สลับบัญชี = ใช้สถานะปุ่มล่าสุด
void TierEnableInit() {
   int  r       = UninitializeReason();
   bool restore = (r == REASON_CHARTCHANGE || r == REASON_RECOMPILE || r == REASON_ACCOUNT);
   ArrayInitialize(g_en, false);
   g_en[2] = InpEnableT2; g_en[3] = InpEnableT3; g_en[4] = InpEnableT4;
   for(int t = 2; t <= 4; t++) {
      if(restore && GlobalVariableCheck(TierGVName(t))) g_en[t] = (GlobalVariableGet(TierGVName(t)) > 0.5);
      GlobalVariableSet(TierGVName(t), g_en[t] ? 1.0 : 0.0);
   }
}

const string BTN_LH = "7LCEA_BTN_LH";

string LHGVName() { return StringFormat("7LCEA_%s_%I64d_LH", _Symbol, InpMagic); }

void LHEnableInit() {
   int  r       = UninitializeReason();
   bool restore = (r == REASON_CHARTCHANGE || r == REASON_RECOMPILE || r == REASON_ACCOUNT);
   g_lh_on = InpEnableLH;
   if(restore && GlobalVariableCheck(LHGVName())) g_lh_on = (GlobalVariableGet(LHGVName()) > 0.5);
   GlobalVariableSet(LHGVName(), g_lh_on ? 1.0 : 0.0);
}

void DrawTierButtons() {
   if(!g_draw) return;
   if(ObjectFind(0, BTN_LH) < 0) {
      ObjectCreate(0, BTN_LH, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, BTN_LH, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, BTN_LH, OBJPROP_XDISTANCE, 10 + 3 * 76);
      ObjectSetInteger(0, BTN_LH, OBJPROP_YDISTANCE, 34);
      ObjectSetInteger(0, BTN_LH, OBJPROP_XSIZE, 70);
      ObjectSetInteger(0, BTN_LH, OBJPROP_YSIZE, 22);
      ObjectSetString(0,  BTN_LH, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, BTN_LH, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, BTN_LH, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, BTN_LH, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0,  BTN_LH, OBJPROP_TEXT, g_lh_on ? "LH ON" : "LH OFF");
   ObjectSetInteger(0, BTN_LH, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_LH, OBJPROP_BGCOLOR, g_lh_on ? clrDarkOrange : clrDimGray);
   ObjectSetInteger(0, BTN_LH, OBJPROP_STATE, false);
   ObjectSetString(0,  BTN_LH, OBJPROP_TOOLTIP, StringFormat("คลิกเพื่อ%sโหมด LH: ยิงเมื่อยืนยันโหนดที่ยอดที่สองต่ำกว่ายอดแรก ≥ %.2f Z แทนตัวจับเวลา (Tick Replay จะเล่นซ้ำใหม่)",
                                                       (g_lh_on ? "ปิด" : "เปิด"), InpLH_MinZ));
   for(int t = 2; t <= 4; t++) {
      string nm = BTN_PREFIX + IntegerToString(t);
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10 + (t - 2) * 76);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 34);
         ObjectSetInteger(0, nm, OBJPROP_XSIZE, 70);
         ObjectSetInteger(0, nm, OBJPROP_YSIZE, 22);
         ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
      ObjectSetString(0,  nm, OBJPROP_TEXT, StageTag(t) + (g_en[t] ? " ON" : " OFF"));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, g_en[t] ? clrSeaGreen : clrDimGray);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP, StringFormat("คลิกเพื่อ%s %s (Tick Replay จะเล่นซ้ำใหม่ตามระดับที่เปิด)", (g_en[t] ? "ปิด" : "เปิด"), StageTag(t)));
   }
}

// สลับโหมด LH → เก็บสถานะ, ล้างการเฝ้า, เล่นซ้ำ Tick Replay ใหม่
void ToggleLH() {
   g_lh_on = !g_lh_on;
   GlobalVariableSet(LHGVName(), g_lh_on ? 1.0 : 0.0);
   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   g_lh_sig_s = false;
   g_lh_sig_b = false;
   ObjectsDeleteAll(0, OBJ_PREFIX + "RP_");
   ReplayReset();
   g_lay_sig     = "";
   g_last_status = StringFormat("โหมด LH %s (ปุ่ม) — Tick Replay เริ่มเล่นซ้ำใหม่", (g_lh_on ? "เปิด" : "ปิด"));
   PrintFormat("🔘 %s", g_last_status);
   DrawTierButtons();
}

// สลับระดับ → เก็บสถานะ, ล้างการเฝ้า, เล่นซ้ำ Tick Replay ใหม่ตามระดับที่เปิด
void ToggleTier(int tier) {
   if(tier < 2 || tier > 4) return;
   g_en[tier] = !g_en[tier];
   GlobalVariableSet(TierGVName(tier), g_en[tier] ? 1.0 : 0.0);
   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   ObjectsDeleteAll(0, OBJ_PREFIX + "RP_");
   ReplayReset();
   g_lay_sig     = "";
   g_last_status = StringFormat("%s %s (ปุ่ม) — Tick Replay เริ่มเล่นซ้ำใหม่", StageTag(tier), (g_en[tier] ? "เปิด" : "ปิด"));
   PrintFormat("🔘 %s", g_last_status);
   DrawTierButtons();
}

// จัดป้ายไม้ (Tick Replay + ไม้จริง) ที่มองเห็นไม่ให้ซ้อนกัน: เรียงตามเวลา, ป้ายที่ทับป้ายก่อนหน้าถูกเลื่อนขึ้น/ลงทีละแถว
//   (ตามขนาดตัวอักษรจริงบนจอ) + เส้นโยงจากจุดเข้าไม้ถึงป้ายที่ถูกเลื่อน — จัดใหม่เมื่อซูม / เลื่อน / สเกลราคา / มีไม้ใหม่
void LayoutTradeLabels() {
   if(!g_draw) return;
   long   first = ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   long   wb    = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   long   hpx   = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   long   wpx   = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   double pmax  = ChartGetDouble(0, CHART_PRICE_MAX);
   double pmin  = ChartGetDouble(0, CHART_PRICE_MIN);
   string sig   = StringFormat("%I64d|%I64d|%I64d|%I64d|%.5f|%.5f|%d|%d|%d|%d", first, wb, hpx, wpx, pmax, pmin, ArraySize(g_rt), ArraySize(g_marks),
                               g_nd_rp_drawn, g_nd_lv_drawn);
   if(sig == g_lay_sig) return;
   g_lay_sig = sig;
   if(hpx <= 0 || pmax <= pmin) return;
   datetime t_from = iTime(_Symbol, PERIOD_CURRENT, (int)first);
   if(t_from == 0) return;
   t_from -= (datetime)(PeriodSeconds(PERIOD_CURRENT) * 60);   // ป้ายทางซ้ายที่ข้อความยาวเข้ามาในจอ
   double ppx = (pmax - pmin) / (double)hpx;

   // 1) รวบรวมป้ายที่อยู่ในช่วงมองเห็น
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
   for(int src = 0; src < 2; src++) {   // โหนด (Replay / EA จริง) — ป้ายอยู่ทางขวาของจุด
      int    cnt = (src == 0) ? g_nd_rp_drawn : g_nd_lv_drawn;
      string pfx = (src == 0) ? OBJ_PREFIX + "RP_N_" : OBJ_PREFIX + "LN_";
      for(int k = 0; k < cnt; k++) {
         NodeRec r;
         if(src == 0) r = g_nd_rp[k]; else r = g_nd_lv[k];
         datetime t = (datetime)(r.v_msc / 1000);
         if(t < t_from) continue;
         string name = NodeLabelName(r, pfx);
         if(ObjectFind(0, name) < 0) continue;
         ArrayResize(nm, n + 1); ArrayResize(tt, n + 1); ArrayResize(pp, n + 1); ArrayResize(rt, n + 1); ArrayResize(cc, n + 1);
         nm[n] = name; tt[n] = t; pp[n] = r.px; rt[n] = false; cc[n] = (r.dir == -1) ? InpClrNodeSell : InpClrNodeBuy;
         n++;
      }
   }
   // 2) เรียงตามเวลา (insertion sort — ป้ายในจอมีไม่มาก)
   for(int a = 1; a < n; a++) {
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
   // 3) วางทีละป้าย: ลองตำแหน่งเดิม แล้วเลื่อน +1, −1, +2, −2, ... แถว จนไม่ทับป้ายที่วางแล้ว
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
      double np = pp[k] - (yy - y) * ppx;   // พิกเซลลงล่าง = ราคาต่ำลง
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
   if(InpZ_Period < 2 || InpFastPeriod < 2) { Print("❌ Period ต้องอย่างน้อย 2"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpLinesBars < 10 || InpLinesBars > 2000) { Print("❌ InpLinesBars ต้องอยู่ระหว่าง 10-2000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpBarZBars < 1 || InpBarZBars > 20000) { Print("❌ InpBarZBars ต้องอยู่ระหว่าง 1-20000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpReplayDays < 1 || InpReplayDays > 60) { Print("❌ InpReplayDays ต้องอยู่ระหว่าง 1-60"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpT2_Z <= 0.0 || InpT3_Z < InpT2_Z || InpT4_Z < InpT3_Z ||
      InpT2_Sec < 0 || InpT3_Sec < 0 || InpNoNewExt_Pts < 0.0 || InpTierLotStep < 0.0 || InpReEntryZStep < 0.0) {
      Print("❌ ค่า Z ระดับวิกฤต (ต้อง T2 ≤ T3 ≤ T4) / เวลาเฝ้า / Lot ต่อระดับ / ระยะ Z เข้าใหม่ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLot <= 0.0) { Print("❌ Lot ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpNodeWindow_Sec < 5 || InpNodeWindow_Sec > ND_MAXW - 1 || InpNodeMinR2 < 0.0 || InpNodeMinR2 > 1.0 ||
      InpNodeMinPast_Sec < 0 || InpNodeMinPast_Sec >= InpNodeWindow_Sec) {
      Print("❌ ค่าโหนดไม่ถูกต้อง (หน้าต่าง 5-60 วิ, R² 0-1, ผ่านยอดแล้ว < หน้าต่าง)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLH_MinZ < 0.0) { Print("❌ InpLH_MinZ ต้องไม่ติดลบ"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpPostTrack_Min < 1 || InpPostTrack_Min > 1440) { Print("❌ InpPostTrack_Min ต้องอยู่ระหว่าง 1-1440"); return(INIT_PARAMETERS_INCORRECT); }
   SecReset(g_lv_sb);
   g_lv_fit.ok = false;
   ZeroMemory(g_lv_ns_s); ZeroMemory(g_lv_ns_b);
   ArrayResize(g_nd_lv, 0);
   g_nd_lv_drawn = 0;
   if(InpTP_Pts <= 0.0 || InpSLPeak_Pts < 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpQuickWindow_Sec < 0 || InpGiveback_Pct < 0.0 || InpGiveback_Pct >= 100.0 || InpGivebackMinPeak_Pts < 0.0) {
      Print("❌ เวลาตัดจบ / กฎคืนกำไร ไม่ถูกต้อง (คืนกำไร 0-99%, ระยะต้องไม่ติดลบ)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   long per = PeriodSeconds(InpZ_Timeframe);
   if(InpSigmaFloorMult < 0.0 || InpBarStartDelay_Sec < 0 || InpBarEndBlock_Sec < 0 ||
      InpBarStartDelay_Sec + InpBarEndBlock_Sec >= per || InpNewsBlock_Min < 0) {
      Print("❌ ค่าพื้นตัวหาร / เวลาต้น-ท้ายแท่ง / ช่วงข่าว ไม่ถูกต้อง");
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

   if(InpNewsFilter && MQLInfoInteger(MQL_TESTER)) Print("ℹ️ ปฏิทินข่าวใช้ไม่ได้ใน Strategy Tester — ไม่กรองช่วงข่าว");
   if(StringFind(_Symbol, "XAU") < 0) PrintFormat("⚠️ EA ออกแบบสำหรับ XAUUSD แต่กำลังรันบน %s", _Symbol);
   if(InpShow7Lines && Period() != InpZ_Timeframe)
      PrintFormat("ℹ️ กราฟเป็น %s แต่ Z ใช้ %s — เส้น 7 เส้นจะคำนวณตาม TF ของกราฟ", EnumToString(Period()), EnumToString(InpZ_Timeframe));
   InitALMAWeights(InpFastPeriod);
   g_line_clr[0] = InpClrMain; g_line_clr[1] = InpClrL1; g_line_clr[2] = InpClrL2; g_line_clr[3] = InpClrL3;
   g_line_clr[4] = InpClrL4;   g_line_clr[5] = InpClrL5; g_line_clr[6] = InpClrL6;
   g_barz_bar = 0;
   ArrayResize(g_zl_names, 0);
   ArrayResize(g_zl_times, 0);
   g_lines_total = 0;
   g_lines_bar   = 0;

   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   g_bar_changed   = false;
   g_last_tick_msc = 0;
   g_zc.ok         = false;
   ReplayReset();
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_last_trail     = 0;
   g_next_try       = 0;
   g_news_loaded    = 0;
   g_news_ok        = false;
   g_prev_close_zr  = 0.0;
   g_prev_close_zs  = 0.0;
   ArrayResize(g_seg_times, 0);
   ArrayResize(g_marks, 0);
   g_marks_bar = 0;
   g_newsviz_loaded = 0;
   ArrayResize(g_newsviz_names, 0);
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   g_last_comment   = "";
   g_line_main = g_line_sell = g_line_buy = 0.0;
   g_line_sma_main = g_line_sma_sell = g_line_sma_buy = 0.0;
   g_live_z_text = ""; g_live_z_y = -1;
   g_lines_status = "ยังไม่ได้วาด";
   ArrayResize(g_activated, 0);
   ArrayResize(g_peak_tk, 0);
   ArrayResize(g_peak_px, 0);
   g_gb_retry = 0;

   RefreshNews(ServerNow());
   ZeroMemory(g_gs); ZeroMemory(g_gb); ZeroMemory(g_gate_none);
   TierEnableInit();
   LHEnableInit();
   g_lay_sig = "";
   RestoreGatesFromHistory();   // กฎในแท่งของแท่งปัจจุบันไม่หายเมื่อรีสตาร์ท

   ObjectsDeleteAll(0, OBJ_PREFIX);
   if(g_draw && InpShow7Lines) RebuildLines();   // ถ้าประวัติยังโหลดไม่ครบ จะลองใหม่ใน OnTimer
   LoadEntryMarksFromHistory();
   DrawTierButtons();

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

   int ts = GetTimeState(ServerNow());
   if(ts == TS_CLOSING) {
      CloseAllPositions();
      return;
   }
   GivebackStep(tk.bid, tk.ask);   // กฎคืนกำไรเช็คทุก Tick (เหมือน Tick Replay)
   LiveSignalStep(g_last_tick_msc, ts, tk.bid, tk.ask, true);
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ / จัดการไม้ (เปิดไล่จี้, ตัดจบตามเวลา, ขยับโล่)
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManagePositions(now);

   // 2. ยิงเมื่อครบเวลาเฝ้า แม้ไม่มี Tick เข้า (ราคา/Z ยังเป็นค่าล่าสุด)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   zok = (bid > 0.0 && ask > 0.0 && UpdateZ(bid));
   if(zok && ts != TS_CLOSING) LiveSignalStep(MathMax(g_last_tick_msc, (long)now * 1000), ts, bid, ask, false);

   // 3. อัปเดตการแสดงผล
   if(g_draw) {
      UpdateZLines();
      UpdateLinesLive();
      UpdateBarZLabels();
      UpdateEntryMarks();
      ReplayStep();
      DrawLiveNodes();
      LayoutTradeLabels();
      LoadNewsHistory();
      if(bid > 0.0) UpdateLiveZLabel(bid);
      UpdateDashboard(ts, now);
      ChartRedraw(0);   // ให้วัตถุแสดงผลแม้ช่วงที่ไม่มี Tick เข้า
   }
}

// คลิกปุ่ม T2-T4 → เปิด/ปิดระดับ | เลื่อน/ซูม/ย่อขยายกราฟ → จัดตำแหน่งป้าย Z สด + ป้ายไม้ใหม่ทันที
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_LH) {
      ToggleLH();
      ChartRedraw(0);
      return;
   }
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BTN_PREFIX) == 0) {
      ToggleTier((int)StringToInteger(StringSubstr(sparam, StringLen(BTN_PREFIX))));
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
   if(!HistoryDealSelect(trans.deal)) return;
   long     pos;
   bool     sl_loss;
   datetime t;
   if(!OutDealInfo(trans.deal, pos, sl_loss, t)) return;
   int      dir, tier;
   double   ext_z;
   datetime t_in;
   if(EntryInfoOfPosition(pos, dir, tier, ext_z, t_in))
      LiveOnClose(dir, pos, tier, ext_z, t_in, t, sl_loss, true);   // ไม้ปิด → กฎในแท่ง + ล้างการเฝ้าฝั่งเดียวกัน
}
//+------------------------------------------------------------------+
