//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Fast Mean-Reversion Z-Score EA for XAUUSD (Indicator v8.82)  |
//+------------------------------------------------------------------+
//
// 🎯 นิยามระบบ (v14)
//  ค่า Z ที่สุดขั้วเกินจริงมักถูกดีดกลับเสมอ (แม้เป็นเทรนด์จริง) → สวนกลับอย่างเดียว ครั้งละ 1 ไม้
//  (ประวัติการเปลี่ยนแปลงทุกเวอร์ชันอยู่ใน README.md)
//
// 📐 Z-Score (TF ของ Z, 20 แท่ง, รวมแท่งปัจจุบันที่ราคา Bid)
//  • Z_reg = (ราคา − เส้นถดถอยเชิงเส้น) / max(StdDev รอบเส้นถดถอย, 0.5 × StdDev ของส่วนต่างราคาต่อแท่ง)
//  • Z_SMA = (ราคา − SMA20) / StdDev20
//
// 📋 ตรรกะการเข้าไม้ (v14.00) — ตรวจ T4 → T3 → T2, เกณฑ์เดียวกันทั้ง SELL (+Z) / BUY (−Z), เปิด/ปิดแต่ละระดับด้วยปุ่มบนกราฟ
//  • T4: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > 3.5 → ยิงทันที (Lot 0.04)
//  • T3: Z ตัวใดตัวหนึ่ง > 3.0 + ไม่มีค่าสุดขั้วใหม่ 2 วิ (Lot 0.03)
//  • T2: Z ทั้งคู่ > 2.5 (แท่งลอย Z_float > 2.0 → ตัวใดตัวหนึ่งก็ได้) + 5 วิ (Lot 0.02)
//    ระดับที่ปิดอยู่ = ข้ามไปตรวจระดับถัดลงมา (เช่น ปิด T4 → Z > 3.5 นับเป็น T3)
//  • T2 ต้องเป็นแท่งลอย Z_float > 1.8 (ราคาเปิดแท่ง − SMA ตอนเปิดแท่ง) ÷ SD20 — T3 / T4 ไม่ต้องลอย
//  • ระหว่างจับเวลา Z หลุดเกณฑ์ได้ (ไม่ยกเลิก, ใช้ระดับลึกสุดที่ไปถึง) — ยกเลิกเมื่อขึ้นแท่งใหม่
//    + การเฝ้าระดับ T2: Z ตัวใดตัวหนึ่งกลับถึง 0 (เส้นกลาง) → ยกเลิกแล้วรอสัญญาณใหม่
//    ชุดออเดอร์ยังไม่จบ = ไม่หาสัญญาณใหม่ (ล้างการเฝ้า)
//  • ตัวกรองตอนวาง: เวลาตลาด (ห้ามเข้า 1 ชม.หลังเปิด / 1 ชม.ก่อนปิดสัปดาห์) + สเปรด | ข่าว = แสดงอย่างเดียว ไม่กรอง
//
// 📋 ออเดอร์ (v14.30): ครบเงื่อนไข → วาง Stop Order 2 ตัว ห่างจากราคาสัญญาณฝั่งละ 1,000 จุด (Lot ตามระดับทั้งคู่)
//  • สวนกลับ: สัญญาณ SELL (Z ขึ้น) = Sell Stop ที่ Bid − 1,000, SL = High ของแท่ง ณ ตอนสัญญาณ + 500 (BUY กลับทิศ)
//            ห่างจากราคาเข้าไม่เกิน 5,000 จุด (v14.31)
//  • ตามน้ำ : สัญญาณ SELL = Buy Stop ที่ Ask + 1,000, SL = ราคาเปิดของแท่งสัญญาณ (BUY กลับทิศ)
//            ราคาเข้าห่างราคาเปิดแท่ง ≤ 2,000 จุด → SL = ราคาเปิดของแท่งก่อนหน้า (ผิดฝั่ง = ใช้ราคาเปิดแท่งสัญญาณ) (v14.31)
//  • ไม่มี TP / โล่ไล่จี้ / เกราะ — ตัดจบที่ราคาปิดของแท่งที่ 2 หลังแท่งที่ออเดอร์ถูกเกี่ยว (= tick แรกของแท่งถัดไป)
//  • จบแท่งสัญญาณแล้วออเดอร์ตัวไหนยังไม่ถูกเกี่ยว → ยกเลิก | เข้าช่วงห้ามเข้าก่อนปิดสัปดาห์ → ยกเลิกออเดอร์รอ
//  • ชุดจบ = ไม่เหลือออเดอร์รอและไม้ที่ถือ (SL ทั้งคู่ / ตัดจบ / ไม่ถูกเกี่ยว) → เริ่มหาสัญญาณใหม่
//  • ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//
// ⏱️ ค่าชี้วัดการกระชาก (v14.10 — บันทึก / แสดงผลอย่างเดียว ไม่มีผลกับการเทรด)
//  • เร็ว: จากครั้งล่าสุดที่ Z ตัวใดตัวหนึ่งตัดขึ้นผ่าน 1.5 ในแท่ง → ถึง 2.5 / 3.0 / 3.5 (วินาที, * = นับจากเวลาเปิดแท่ง) + อัตรา Z/วิ
//  • ช่วง Z ของแท่ง: เปิด / สูง / ต่ำ / ปิด (Z_reg, Z_SMA)
//  • ค้าง: เวลาที่ Z ตัวใดตัวหนึ่ง ≥ 2.0 (ต่อเนื่อง / นานสุด / รวมในแท่ง) + แท่ง M15 ติดกันที่ยอด / ราคาปิด Z ≥ 2.0
//  • K2: จำนวนครั้งที่ทำยอดใหม่ของแท่ง ภายใน 60 วิก่อนยอดล่าสุด
//  • แท่งสด = เวลาจริงจาก tick ที่ EA เห็น, แท่งย้อนหลัง = จาก tick ของ Tick Replay (เก่ากว่านั้นมีแค่ค่าจาก OHLC)
//  • ป้ายบนแท่ง 2 แถว + จัดตำแหน่งไม่ให้ซ้อน (ไม่มีที่ = ซ่อน) | ชี้เมาส์ที่แท่ง = กล่องรายละเอียดมุมซ้ายล่าง
//  • Tick Replay: CSV แท่ง (MQL5/Files/7LCEA_Bars_<symbol>.csv) ทุกแท่งที่ Z ≥ 2.0 + ผล 60 นาทีหลังยอด (สวนกลับ 2σ / พุ่งต่อ +500)
//  • TF ใหญ่ (v14.20, ค่าเริ่มต้น M30): แท่งที่ Z ถึง T2-T4 ตามกฎเดียวกับ EA → กรอบเส้นประ + ป้าย "M30 T3" (สี T2 เหลือง / T3 ส้ม / T4 แดง)
//
// 🧪 Tick Replay (บนกราฟ, ไม่ใช่ Strategy Tester)
//  • เล่นซ้ำ tick จริงย้อนหลังด้วยกติกาเดียวกับ EA → มาร์กบนกราฟ + สรุปบน Dashboard
//  • บันทึกปัจจัย "ใช่ยอดหรือยัง" ณ ตอนยิง + ความเร็ว Z + ระยะกำไรระหว่างถือ → MQL5/Files/7LCEA_Replay_<symbol>.csv
//    A ระยะฉีกจาก High / Low ของ 2 แท่งก่อน ÷ ช่วงแท่งเฉลี่ย 20 แท่ง | B แรงส่ง 30 วิล่าสุด เทียบ 30 วิก่อนหน้า
//    C Z ลดจากค่าสุดขั้ว | D ถอยจากยอดเทียบระยะฉีก | E อัตรา tick 15 วิล่าสุด เทียบ 60 วิก่อนหน้า
//  (เส้นบริบท VWAP / Keltner / TF ใหญ่ / วันก่อน / EMA ยาว แยกไปอยู่ใน Indicators/Seven_Lines_Context_Ind.mq5)
//
// ⚡ การประหยัด CPU
//  • Z: แคชผลรวมของแท่งที่ปิดแล้ว คำนวณใหม่เฉพาะตอนขึ้นแท่งใหม่ (ต่อ Tick ไม่กี่บรรทัดคณิต)
//  • จัดการไม้ / Dashboard ทำบน OnTimer 1 วินาที, เกราะ / ความเร็ว Z ทำต่อ Tick
//  • Dashboard เขียนเฉพาะเมื่อข้อความเปลี่ยน, ไม่วาดอะไรใน Tester แบบไม่เปิด Visual
//
#property copyright   "Commander's Quant System"
#property version     "14.31"
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
input double          InpT4_Z              = 3.50;       // T4: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ → ยิงทันที (ไม่ต้องลอย)
input bool            InpFloatFilter       = true;       // T2 ต้องเป็นแท่งลอยตัว: ราคาเปิดแท่งพ้นเส้น SMA ตอนเปิดแท่ง (SELL เหนือ / BUY ใต้)
input double          InpFloatMin          = 1.80;       // T2 ทำงานเมื่อแท่งลอย Z_float > ค่านี้ (หน่วย SD20, 0 = แค่ราคาเปิดพ้น SMA)
input double          InpNoNewExtEps       = 0.01;       // Z ต้องเกินค่าสุดขั้วเดิมเท่านี้ถึงนับเป็นค่าใหม่
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot ฐาน (T2 = ฐาน + step = 0.02)
input double          InpTierLotStep       = 0.01;       // Lot เพิ่มต่อระดับ (T2 = ฐาน+step, T3 = +2·step, T4 = +3·step)
input double          InpStopDist_Pts      = 1000.0;     // Stop Order ห่างจากราคาสัญญาณฝั่งละกี่จุด (Buy Stop = Ask + / Sell Stop = Bid −)
input double          InpSLPeak_Pts        = 500.0;      // SL ฝั่งสวนกลับ = High (สัญญาณ SELL) / Low (สัญญาณ BUY) ของแท่ง ณ ตอนสัญญาณ ± ระยะนี้ (จุด)
input double          InpCounterMaxSL_Pts  = 5000.0;     // SL ฝั่งสวนกลับห่างจากราคาเข้าได้สูงสุดกี่จุด (รวม buffer แล้ว, 0 = ไม่จำกัด)
input double          InpTrendNearOpen_Pts = 2000.0;     // ฝั่งตามน้ำ: ราคาเข้าห่างราคาเปิดแท่ง ≤ ค่านี้ → SL ใช้ราคาเปิดของแท่งก่อนหน้า (0 = ปิด)
input int             InpExitBars          = 2;          // ตัดจบที่ราคาปิดของแท่งที่ N หลังแท่งที่ออเดอร์ถูกเกี่ยว (TF ของ Z)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์ (ต่อท้ายด้วยระดับ / C สวน, F ตาม / Z สุดขั้ว)

input group "=== 3. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpNoTradeBeforeClose_Min = 60;    // ห้ามเข้าไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input int             InpNewsBlock_Min     = 5;          // ข่าว (แสดงอย่างเดียว ไม่กรอง): แถบก่อน / หลังเวลาข่าวออกกี่นาที
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าวที่แสดง

input group "=== 4. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowZLines        = true;       // แสดงเส้นแนวนอนระดับ Z ชุด Regression
input bool            InpShowSmaZLines     = true;       // แสดงเส้นแนวนอนระดับ Z ชุด SMA20 (เปรียบเทียบ)
input bool            InpShowLiveZ         = true;       // แสดงป้ายค่า Z สด ณ ราคาปัจจุบัน
input int             InpLiveZFontSize     = 11;         // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;         // ระยะห่างป้าย Z สดจากขอบขวาของกราฟ (พิกเซล)
input bool            InpShowBarZ          = true;       // แสดงป้ายค่า Z บนแท่งที่ Z ถึงเกณฑ์
input bool            InpShowFloatMark     = true;       // แสดงป้าย Z_float บนแท่งที่ราคาเปิดลอยพ้น SMA (ช่วงแท่งเดียวกับป้าย Z)
input double          InpFloatMarkZ        = 1.00;       // ป้าย Z_float: แสดงเมื่อ Z_float > ค่านี้
input bool            InpFloatMarkLive     = true;       // ป้าย Z_float: แท่งปัจจุบันแสดงค่าเสมอตั้งแต่เปิดแท่ง (ไม่ถึงเกณฑ์ = สีเทา)
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย (สูงสุด 20,000)
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input bool            InpShowZSpeed        = true;       // ป้าย Z บนแท่ง: แถวที่ 2 = เร็ว / ค้าง / K2 / แท่งติดกัน
input double          InpSpeedFromZ        = 1.50;       // ความเร็ว: เริ่มจับเมื่อ Z ตัวใดตัวหนึ่งตัดขึ้นผ่านค่านี้ (ครั้งล่าสุดในแท่ง)
input double          InpZoneZ             = 2.00;       // เวลาค้างโซน / แท่งติดกัน: Z ตัวใดตัวหนึ่ง ≥ ค่านี้
input int             InpK2_Window_Sec     = 60;         // K2: นับครั้งที่ทำยอดใหม่ของแท่ง ภายในกี่วินาทีก่อนยอดล่าสุด
input bool            InpShowBarPanel      = true;       // กล่องรายละเอียดแท่ง (ชี้เมาส์ที่แท่ง → ค่าทั้งหมด, มุมซ้ายล่าง)
input int             InpPanelFontSize     = 9;          // ขนาดตัวอักษรกล่องรายละเอียดแท่ง
input bool            InpShowHTF           = true;       // แสดงกรอบแท่ง TF ใหญ่ (InpHTF) ที่ Z ถึง T2-T4 (กฎเดียวกับ EA + ปุ่ม T2-T4)
input ENUM_TIMEFRAMES InpHTF               = PERIOD_M30; // TF ใหญ่ที่ตรวจ T2-T4 (ต้องใหญ่กว่าและหารลงตัวด้วย TF ของ Z)
input bool            InpBarCSV            = true;       // Tick Replay: บันทึกทุกแท่งที่ Z ≥ InpZoneZ + ผลสวนกลับ / พุ่งต่อ ลง CSV แท่ง
input int             InpOutcomeMin        = 60;         // CSV แท่ง: ดูผลภายในกี่นาทีหลังยอดของแท่ง
input double          InpOutcomeSigma      = 2.00;       // CSV แท่ง: ราคาถอยจากยอดกี่ σ (SD20) = สวนกลับ (ทะลุยอด + InpSLPeak_Pts = พุ่งต่อ)
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กสัญญาณที่ถูกตัวกรองทิ้ง
input bool            InpReplayCSV         = true;       // Tick Replay: บันทึกปัจจัยตอนยิง + ผล + ระยะกำไรระหว่างถือ ลง CSV (MQL5/Files)
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (แสดงอย่างเดียว ไม่กรอง, ใช้ไม่ได้ใน Tester)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium บนกราฟด้วย

input group "=== 5. สี ==="
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
input color           InpClrBarZInfo       = clrKhaki;          // ป้ายบนแท่งแถวที่ 2: เร็ว / ค้าง / K2 / แท่งติดกัน
input color           InpClrHTF2           = clrYellow;         // กรอบ TF ใหญ่: ถึง T2
input color           InpClrHTF3           = clrOrange;         // กรอบ TF ใหญ่: ถึง T3
input color           InpClrHTF4           = clrRed;            // กรอบ TF ใหญ่: ถึง T4
input color           InpClrPanelBg        = C'20,24,32';       // กล่องรายละเอียดแท่ง: พื้นหลัง
input color           InpClrPanelText      = clrGainsboro;      // กล่องรายละเอียดแท่ง: ตัวอักษร
input color           InpClrPanelHead      = clrGold;           // กล่องรายละเอียดแท่ง: หัวข้อ
input color           InpClrEntrySell      = clrRed;            // มาร์กจุดเปิด SELL
input color           InpClrEntryBuy       = clrLime;           // มาร์กจุดเปิด BUY
input color           InpClrEntryGap       = clrYellow;         // เส้นประ + ตัวเลขระยะห่างถึงปลายไส้
input color           InpClrSimSell        = clrViolet;         // มาร์กจำลอง: SELL
input color           InpClrSimBuy         = clrPaleGreen;      // มาร์กจำลอง: BUY
input color           InpClrSimWin         = clrLimeGreen;      // มาร์กจำลอง: เส้นเข้า→ออก ไม้กำไร
input color           InpClrSimLoss        = clrTomato;         // มาร์กจำลอง: เส้นเข้า→ออก ไม้ขาดทุน
input color           InpClrPendCounter    = clrOrchid;         // จำลอง: ระดับ Stop ฝั่งสวนกลับ
input color           InpClrPendTrend      = clrDodgerBlue;     // จำลอง: ระดับ Stop ฝั่งตามน้ำ
input color           InpClrSimBlocked     = clrDimGray;        // มาร์กจำลอง: สัญญาณที่ถูกตัวกรองทิ้ง
input color           InpClrNewsLine       = clrMediumPurple;   // เส้นเวลาข่าว
input color           InpClrNewsZone       = C'45,35,70';       // แถบแท่งข่าว

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define TS_OPEN       0
#define TS_WAIT_OPEN  1
#define TS_CLOSING    2
#define TS_CLOSED     3
#define TS_WAIT_CLOSE 4   // ใกล้ตลาดปิดสัปดาห์: ห้ามเข้าไม้ใหม่ (ไม้ที่ถืออยู่รันต่อจนถึงเวลาปิดทุกไม้)

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
};

// ความเร็วของ Z ในแท่งเดียว — ใช้ร่วมกันทั้ง EA จริงและ Tick Replay
//   เริ่มจับ = ครั้งล่าสุดที่ Z ตัดขึ้นผ่าน InpSpeedFromZ (แท่งเปิดมาเกินอยู่แล้ว = เวลาเปิดแท่ง, star)
//   sec[k] = วินาทีจากจุดเริ่มถึง Z แตะเกณฑ์ T2 / T3 / T4 ครั้งแรก (-1 = ยังไม่ถึง)
struct ZSpeed {
   long   start;      // msc ที่เริ่มจับ (0 = Z ยังต่ำกว่าจุดเริ่ม)
   bool   star;       // เริ่มจากเวลาเปิดแท่ง
   bool   above;      // Z อยู่เหนือจุดเริ่มตอนนี้
   bool   seen;       // เห็น tick ของแท่งนี้แล้ว
   double z0;         // Z ตอนเริ่มจับ (ใช้คิดอัตราพุ่ง Z / วินาที)
   int    sec[3];     // T2 / T3 / T4
   bool   star_k[3];  // ค่าใน sec[k] เริ่มจากเวลาเปิดแท่ง
};

// สถิติจาก tick ของแท่งหนึ่ง ฝั่งหนึ่ง (SELL = Z ขึ้น / BUY = Z ลง, ทุกค่าเป็นทิศของการกระชาก)
struct SideStat {
   ZSpeed sp[3];        // ความเร็ว: 0 = Z_reg, 1 = Z_SMA, 2 = รวม (Z ตัวที่สูงกว่า)
   double peak_z;       // Z สูงสุดในแท่ง (ตัวที่สูงกว่า)
   long   zone_cum_ms;  // เวลารวมที่ Z ≥ InpZoneZ ในแท่ง
   long   zone_max_ms;  // ค้าง ≥ InpZoneZ ต่อเนื่องนานสุดในแท่ง (นับตั้งแต่เปิดแท่ง)
   int    k2;           // K2: จำนวนครั้งที่ทำยอดใหม่ของแท่ง ภายใน InpK2_Window_Sec ก่อนยอดล่าสุด
   int    k2_max;       // K2 สูงสุดในแท่ง
   double ext_px;       // ยอดราคาของแท่งจาก tick (SELL = High / BUY = Low)
   long   ext_msc;      // เวลาที่ทำยอดล่าสุด
   double ext_sd;       // SD20 ณ ยอดล่าสุด
   double back_px;      // ราคาถอยไกลสุดหลังยอดล่าสุด
   long   rev_msc;      // เวลาที่ถอยถึง InpOutcomeSigma × σ หลังยอดล่าสุด (0 = ยัง)
};

// สถิติของแท่งหนึ่ง (เก็บไว้แสดงป้ายบนแท่ง / กล่องรายละเอียด): sd[0] = SELL, sd[1] = BUY
struct BarSpeed {
   datetime bar;
   bool     fresh;    // เห็น tick ตั้งแต่เปิดแท่ง (ไม่ได้เริ่มจับกลางแท่ง)
   SideStat sd[2];
};

// สถานะต่อเนื่องข้าม tick ของแต่ละฝั่ง: ค้างโซน + เวลาที่ทำยอดใหม่ (วงแหวนสำหรับ K2)
#define K2_RING 512
struct SideTrack {
   bool   in_zone;
   long   zone_from;          // msc ที่เริ่มค้าง ≥ InpZoneZ รอบนี้ (ข้ามแท่งได้)
   long   ring[K2_RING];
   int    head;
   int    cnt;
};

// ตัวติดตามต่อ tick (EA จริง 1 ตัว / Tick Replay 1 ตัว)
struct SpeedTracker {
   BarSpeed  cur;             // แท่งที่กำลังเดิน
   BarSpeed  closed;          // แท่งที่เพิ่งปิด (closed_new = true ใน tick ที่ขึ้นแท่งใหม่)
   bool      closed_new;
   SideTrack tr[2];
   long      last_msc;
};

// ค่า Z ของแท่ง (จาก OHLC) สำหรับป้ายบนแท่ง
struct BarView {
   datetime t;
   double   hi, lo, open;
   bool     ok[2];        // [0] = ที่ High (SELL), [1] = ที่ Low (BUY)
   double   zr[2];
   double   zs[2];
   double   fz;           // Z_float (+ = ราคาเปิดเหนือ SMA)
   int      peak_n[2];    // แท่งติดกันจนถึงแท่งนี้ที่ยอด Z ≥ InpZoneZ (แต่ละฝั่ง)
};

// แคชผลรวมของแท่งที่ปิดแล้ว (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct ZCache {
   bool   ok;
   double ref, sY, sXY, sYY, sD, sDD, last_close;
   double prev_zr, prev_zs;   // Z ตอนปิดแท่งล่าสุด
};

const double NEAR_ZONE = 0.5;   // ระยะ "ใกล้เกณฑ์" สำหรับสีป้าย Z
const int    SPEED_KEEP = 10000; // จำนวนแท่งสูงสุดที่เก็บสถิติ tick ของแท่ง
const int    STREAK_MAX = 60;    // นับแท่งติดกันย้อนหลังสูงสุดกี่แท่ง

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

// --- เฝ้าค่าสุดขั้ว (EA จริง) ---
WatchState g_wsell;
WatchState g_wbuy;
SpeedTracker g_trk_live;               // สถิติ tick ของแท่งปัจจุบัน (tick สด)
SpeedTracker g_trk_rp;                 // สถิติ tick ของแท่งที่ Tick Replay กำลังเล่น
BarSpeed   g_spd_hist[];               // สถิติ tick ของแท่งที่ผ่านมา (สด + Tick Replay) เรียงตามเวลาแท่ง
int        g_prev_pk[2];               // แท่งติดกันที่ยอด Z ≥ InpZoneZ จนถึงแท่งที่ปิดล่าสุด (SELL / BUY)
int        g_prev_cl[2];               // แท่งติดกันที่ Z ปิดแท่ง ≥ InpZoneZ จนถึงแท่งที่ปิดล่าสุด
int        g_lbl_ver        = 0;       // ป้ายบนแท่งเปลี่ยน → จัดตำแหน่งใหม่
datetime   g_pn_bar         = 0;       // แท่งที่กล่องรายละเอียดแสดงอยู่ (0 = แท่งปัจจุบัน)
int        g_pn_side        = -1;      // ฝั่งที่เมาส์ชี้ (−1 = เลือกฝั่งที่ Z สูงกว่า)
string     g_pn_text        = "";
bool       g_htf_ok         = false;   // InpHTF ใช้ได้ (ใหญ่กว่าและหารลงตัวด้วย TF ของ Z)
datetime   g_htf_bar        = 0;       // แท่ง TF ใหญ่ปัจจุบันตอนอัปเดตกรอบล่าสุด (0 = วาดใหม่ทั้งชุด)
bool       g_en[5];                    // เปิดใช้ระดับ T2-T4 (ปุ่มบนกราฟ, index = ระดับ)
string     g_lay_sig        = "";      // สถานะกราฟตอนจัดป้ายไม้ล่าสุด
bool       g_bar_changed    = false;   // ขึ้นแท่งใหม่ (TF ของ Z) → ล้างการเฝ้า
long       g_last_tick_msc  = 0;
datetime   g_next_try       = 0;
string     g_last_status    = "เริ่มทำงาน";
datetime   g_ord_retry      = 0;       // ลบออเดอร์รอ / ตัดจบไม่สำเร็จ → ลองใหม่หลังเวลานี้

// --- Session ---
WeekBlock g_blocks[];
int       g_block_count  = 0;
bool      g_always_open  = false;
bool      g_session_ok   = false;
datetime  g_blk_open     = 0;
datetime  g_blk_close    = 0;
bool      g_blk_valid    = false;

// --- UI ---
string    g_last_comment = "";
double    g_line_main    = 0.0;
double    g_line_sell    = 0.0;
double    g_line_buy     = 0.0;
double    g_line_sma_main = 0.0;
double    g_line_sma_sell = 0.0;
double    g_line_sma_buy  = 0.0;
string    g_live_z_text  = "";
int       g_live_z_y     = -1;

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

// โหลดข่าว High ของสกุลที่เลือก ตั้งแต่ต้นช่วง Tick Replay ถึง +24 ชม. (ทุก 10 นาที) — แสดงอย่างเดียว ไม่กรองการเข้าไม้
void RefreshNews(datetime now) {
   if(!NewsEnabled() || !InpShowNewsHistory) return;
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

// ข่าวที่อยู่ในช่วง ±InpNewsBlock_Min นาทีจากเวลา t → index ใน g_news_times (−1 = ไม่มี) — ใช้แสดงผลเท่านั้น
int NewsNear(datetime t) {
   if(InpNewsBlock_Min <= 0 || !NewsEnabled()) return -1;
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
   if(!InpShowNewsHistory) return "";
   if(!NewsEnabled()) return "📰 ปฏิทินข่าวใช้ไม่ได้ใน Tester";
   int k = NewsNear(now);
   if(k >= 0) return StringFormat("📰 ช่วงข่าว (แสดงอย่างเดียว ไม่กรอง): %s %s", TimeToString(g_news_times[k], TIME_MINUTES), g_news_names[k]);
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
// 🎯 SIGNAL: เฝ้าค่าสุดขั้ว No new high/low (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
// แท่ง (TF ของ Z) ที่เวลา t อยู่
datetime BarStartOf(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   return (per > 0) ? (datetime)((long)t - (long)t % per) : t;
}

// Z สุดขั้วในทิศของการกระชาก (ตัวที่สูงกว่าระหว่าง Z_reg / Z_SMA)
double ZHi(int dir, double zr, double zs) { return MathMax((dir == -1) ? zr : -zr, (dir == -1) ? zs : -zs); }

// ระดับวิกฤต (ตรวจ T4 → T3 → T2, ข้ามระดับที่ปิดด้วยปุ่ม), zf = Z_float ในทิศของฝั่งนี้:
//   4 = Z ตัวใดตัวหนึ่ง > T4 | 3 = > T3 (T3 / T4 ไม่ต้องลอย)
//   2 = Z ทั้งคู่ > T2 (ตัวใดตัวหนึ่งเมื่อ zf > InpT2EitherFloat, ต้องลอย zf > InpFloatMin) | 0 = ไม่ถึง
int TierOf(int dir, double zr, double zs, double zf) {
   double a_r = (dir == -1) ? zr : -zr;
   double a_s = (dir == -1) ? zs : -zs;
   double hi  = MathMax(a_r, a_s), lo = MathMin(a_r, a_s);
   if(g_en[4] && hi > InpT4_Z) return 4;
   if(g_en[3] && hi > InpT3_Z) return 3;
   if(!g_en[2] || (InpFloatFilter && zf <= InpFloatMin)) return 0;
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
}

// อัปเดตการเฝ้า: เริ่มเมื่อเข้าเงื่อนไขระดับใดระดับหนึ่ง, Z ตัวใดทำค่าสุดขั้วใหม่ = นับเวลาใหม่,
// ระดับ = ลึกสุดที่ไปถึง (Z หลุดเกณฑ์ระหว่างจับเวลาได้ ไม่ลดระดับ)
//   การเฝ้าระดับ T2: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่งกลับถึง 0 → ยกเลิกแล้วรอสัญญาณใหม่
//   zf = Z_float ในทิศของฝั่งนี้ — ยกเลิกจากภายนอก: ขึ้นแท่งใหม่ / ไม้ปิด
void WatchUpdate(WatchState &w, int dir, double zr, double zs, long now_msc, double bid, double ask, double zf) {
   int tier = TierOf(dir, zr, zs, zf);
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
      return;
   }
   bool nr, ns;
   if(dir == -1) { nr = (zr > w.ext_r + InpNoNewExtEps); ns = (zs > w.ext_s + InpNoNewExtEps); }
   else          { nr = (zr < w.ext_r - InpNoNewExtEps); ns = (zs < w.ext_s - InpNoNewExtEps); }
   if(nr) w.ext_r = zr;
   if(ns) w.ext_s = zs;
   if(nr || ns) w.last_new = now_msc;
   if(tier > w.tier) w.tier = tier;
   w.max_tier = w.tier;
   double a_r = (dir == -1) ? zr : -zr, a_s = (dir == -1) ? zs : -zs;
   if(w.tier <= 2 && (a_r <= 0.0 || a_s <= 0.0)) WatchReset(w);   // T2: Z กลับถึงเส้นกลาง = สัญญาณจบ
}

long WatchDeadline(const WatchState &w) { return w.last_new + TierWaitMs(w.tier); }
bool WatchReady(const WatchState &w, long now_msc) { return w.active && now_msc >= WatchDeadline(w); }

// SL ทุกระดับ: High (SELL) / Low (BUY) ของแท่ง (TF ของ Z) ณ ตอนเปิดไม้ ± InpSLPeak_Pts
double SLPrice(int dir, double bar_hi, double bar_lo) {
   double d = PtsToPrice(InpSLPeak_Pts);
   return (dir == -1) ? bar_hi + d : bar_lo - d;
}

// ที่มาของ SL (บันทึก / แสดงผล)
#define SLM_PEAK      0   // สวน: ยอดแท่ง ± InpSLPeak_Pts
#define SLM_PEAK_CAP  1   // สวน: ห่างเกินเพดาน → ราคาเข้า ± InpCounterMaxSL_Pts
#define SLM_OPEN      2   // ตาม: ราคาเปิดของแท่งสัญญาณ
#define SLM_OPEN_PREV 3   // ตาม: ราคาเข้าใกล้ราคาเปิดแท่ง → ราคาเปิดของแท่งก่อนหน้า

// SL ฝั่งสวน (dir = ทิศของไม้): ยอดแท่ง ± InpSLPeak_Pts แต่ห่างจากราคาเข้าไม่เกิน InpCounterMaxSL_Pts
double CounterSL(int dir, double entry, double bar_hi, double bar_lo, int &mode) {
   double sl = SLPrice(dir, bar_hi, bar_lo);
   mode = SLM_PEAK;
   if(InpCounterMaxSL_Pts > 0.0) {
      double cap = PtsToPrice(InpCounterMaxSL_Pts);
      if(dir == -1 && sl > entry + cap) { sl = entry + cap; mode = SLM_PEAK_CAP; }
      if(dir ==  1 && sl < entry - cap) { sl = entry - cap; mode = SLM_PEAK_CAP; }
   }
   return sl;
}

// SL ฝั่งตาม (dir = ทิศของไม้): ราคาเปิดของแท่งสัญญาณ — ราคาเข้าห่างไม่เกิน InpTrendNearOpen_Pts
//   → ราคาเปิดของแท่งก่อนหน้า (ถ้าอยู่ฝั่งขาดทุนของราคาเข้า ไม่งั้นใช้ราคาเปิดแท่งสัญญาณตามเดิม)
double TrendSL(int dir, double entry, double open0, double open1, int &mode) {
   mode = SLM_OPEN;
   if(InpTrendNearOpen_Pts <= 0.0 || MathAbs(entry - open0) > PtsToPrice(InpTrendNearOpen_Pts)) return open0;
   bool valid = (open1 > 0.0) && ((dir == 1) ? open1 < entry : open1 > entry);
   if(!valid) return open0;
   mode = SLM_OPEN_PREV;
   return open1;
}

string SLModeCode(int m) {
   switch(m) {
      case SLM_PEAK_CAP:  return "PEAK_CAP";
      case SLM_OPEN:      return "OPEN";
      case SLM_OPEN_PREV: return "OPEN_PREV";
   }
   return "PEAK";
}

string SLModeText(int m) {
   switch(m) {
      case SLM_PEAK_CAP:  return StringFormat("เพดาน %.0f จุดจากราคาเข้า (ยอดแท่ง ± %.0f ห่างเกิน)", InpCounterMaxSL_Pts, InpSLPeak_Pts);
      case SLM_OPEN:      return "ราคาเปิดแท่งสัญญาณ";
      case SLM_OPEN_PREV: return StringFormat("ราคาเปิดแท่งก่อนหน้า (ราคาเข้าห่างเปิดแท่ง ≤ %.0f)", InpTrendNearOpen_Pts);
   }
   return StringFormat("ยอดแท่ง ± %.0f", InpSLPeak_Pts);
}

// ตัวกรองตอนยิง (ใช้ร่วมกัน) — เวลาตลาด (1 ชม.หลังเปิด / ก่อนปิดสัปดาห์) + เพดานสเปรด
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
   if(t >= c - (datetime)(InpNoTradeBeforeClose_Min * 60)) return TS_WAIT_CLOSE;
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

// เวลาเริ่มช่วงห้ามเข้าก่อนตลาดปิดสัปดาห์ ของช่วงตลาดที่ครอบเวลา t (0 = ไม่มี)
datetime NoEntryStartAt(datetime t) {
   if(!g_session_ok || g_always_open) return 0;
   datetime o, c;
   if(!LocateBlockAt(t, o, c)) return 0;
   return c - (datetime)(MathMax(InpNoTradeBeforeClose_Min, InpCloseBeforeClose_Min) * 60);
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

//====================================================================
// 💼 ORDER MANAGEMENT
//====================================================================
// วาง Stop Order 1 ตัว: dir = ทิศของไม้ (+1 BUY STOP ที่ Ask + dist / −1 SELL STOP ที่ Bid − dist), kind "C" สวน / "F" ตาม
//   คอมเมนต์ "<InpOrderComment> T3 C X3.25" (X = Z สุดขั้วในทิศกระชาก) — เคารพ Stops Level ทั้งราคาเข้าและ SL
bool PlaceStop(int dir, int stage, string kind, double bid, double ask, double sl, string sl_note, datetime expire, double ext_z, double &price_out) {
   double lot   = TierLot(stage);
   double dist  = PtsToPrice(InpStopDist_Pts);
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double price = (dir == 1) ? ask + dist : bid - dist;
   if(dir == 1) price = MathMax(price, ask + stops + _Point);
   else         price = MathMin(price, bid - stops - _Point);
   price = ND(price);
   if(dir == 1) sl = MathMin(sl, price - stops - _Point);   // SL ต้องอยู่ฝั่งขาดทุนของราคาเข้า
   else         sl = MathMax(sl, price + stops + _Point);
   sl = ND(sl);
   string cmt = StringFormat("%s %s %s X%.2f", InpOrderComment, StageTag(stage), kind, ext_z);
   ENUM_ORDER_TYPE_TIME tt    = ORDER_TIME_GTC;
   datetime             exp_t = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0) { tt = ORDER_TIME_SPECIFIED; exp_t = expire; }
   bool ok = (dir == 1) ? trade.BuyStop (lot, price, _Symbol, sl, 0.0, tt, exp_t, cmt)
                        : trade.SellStop(lot, price, _Symbol, sl, 0.0, tt, exp_t, cmt);
   uint rc = trade.ResultRetcode();
   price_out = price;
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED)) {
      PrintFormat("✅ วาง %s %s %s %.2f lot @ %s | SL %s (%s, ห่าง %.0f จุด) | หมดอายุ %s",
                  StageTag(stage), (kind == "C" ? "สวน" : "ตาม"), (dir == 1 ? "BUY STOP" : "SELL STOP"), lot,
                  DoubleToString(price, _Digits), DoubleToString(sl, _Digits), sl_note,
                  PriceToPts(MathAbs(price - sl)), TimeToString(expire, TIME_MINUTES));
      return true;
   }
   PrintFormat("❌ วาง %s %s %s ไม่สำเร็จ: %u %s", StageTag(stage), (kind == "C" ? "สวน" : "ตาม"), (dir == 1 ? "BUY STOP" : "SELL STOP"),
               rc, trade.ResultRetcodeDescription());
   return false;
}

int OurPositionsTotal() {
   int b, s;
   CountPositions(b, s);
   return b + s;
}

bool IsOurOrder() {
   return (OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol);
}

int OurPendingTotal() {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(ticket != 0 && IsOurOrder()) n++;
   }
   return n;
}

// ชุดออเดอร์ยังไม่จบ = ยังมีออเดอร์รอหรือไม้ที่ถืออยู่ (รู้สถานะได้แม้ EA รีสตาร์ท)
bool SetActive() { return OurPositionsTotal() > 0 || OurPendingTotal() > 0; }

// ระดับ (T1-T4) จากคอมเมนต์ของดีลเปิด เช่น "7L-CNT T3 C X3.25" (0 = อ่านไม่ได้) — ใช้กับมาร์กจุดเปิดไม้
int TierFromComment(string c) {
   for(int t = 4; t >= 1; t--)
      if(StringFind(c, " T" + IntegerToString(t) + " ") >= 0) return t;
   return 0;
}

// ฝั่งของออเดอร์จากคอมเมนต์: "ตาม" (F) / "สวน" (C)
string KindFromComment(string c) { return (StringFind(c, " F ") >= 0) ? "ตาม" : "สวน"; }

//--------------------------------------------------------------------
// 🎯 วางชุดออเดอร์ (EA จริง)
//--------------------------------------------------------------------
// ครบเวลาเฝ้าของระดับ (T2 5 วิ / T3 2 วิ / T4 ทันที) → ตัวกรอง → วาง Stop สวน + Stop ตาม (ติดตัวกรอง = ทิ้งสัญญาณ)
//   dir = ทิศของฝั่งสวน (−1 = สัญญาณ SELL จาก Z ขึ้น / +1 = สัญญาณ BUY จาก Z ลง)
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

   double   hi     = MathMax(g_bar0_hi, bid);
   double   lo     = (g_bar0_lo > 0.0) ? MathMin(g_bar0_lo, bid) : bid;
   double   ext_z  = ZHi(dir, w.ext_r, w.ext_s);
   datetime expire = BarStartOf(now) + (datetime)PeriodSeconds(InpZ_Timeframe);
   double   pc = 0.0, pf = 0.0;
   double   dist   = PtsToPrice(InpStopDist_Pts);
   double   ec     = (dir == 1) ? ask + dist : bid - dist;   // ราคาเข้าของขาสวน / ขาตาม
   double   ef     = (dir == 1) ? bid - dist : ask + dist;
   int      mc, mf;
   double   slc    = CounterSL(dir, ec, hi, lo, mc);
   double   slf    = TrendSL(-dir, ef, g_bar0_open, iOpen(_Symbol, InpZ_Timeframe, 1), mf);
   bool     okc = PlaceStop( dir, tier, "C", bid, ask, slc, SLModeText(mc), expire, ext_z, pc);
   bool     okf = PlaceStop(-dir, tier, "F", bid, ask, slf, SLModeText(mf), expire, ext_z, pf);
   if(okc || okf) {
      g_last_status = StringFormat("วางชุด %s %s (Lot %.2f) | สวน %s @ %s%s | ตาม %s @ %s%s | สุดขั้ว R %+.2f / S %+.2f",
                                   side, StageTag(tier), TierLot(tier),
                                   (dir == -1 ? "SELL STOP" : "BUY STOP"), DoubleToString(pc, _Digits), (okc ? "" : " ❌"),
                                   (dir == -1 ? "BUY STOP" : "SELL STOP"), DoubleToString(pf, _Digits), (okf ? "" : " ❌"),
                                   w.ext_r, w.ext_s);
      PrintFormat("   📈 สถิติแท่ง ณ ตอนสัญญาณ (ฝั่งกระชาก): %s", LiveStatText(dir == -1 ? 0 : 1, g_last_tick_msc));
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
   } else {
      g_next_try    = now + 1;   // กันยิงคำสั่งรัว ๆ เมื่อโบรกปฏิเสธ (ยังเฝ้าต่อ)
      g_last_status = side + " วางชุดออเดอร์ไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

// เรียกทุก Tick และทุก 1 วินาที — ขึ้นแท่งใหม่ = ล้างการเฝ้า, ชุดออเดอร์ยังไม่จบ = ไม่หาสัญญาณใหม่ (ล้างการเฝ้า)
//   (เวลาตลาด / สเปรด ตรวจตอนวางใน LiveFire)
void LiveSignalStep(long now_msc, int ts, double bid, double ask, bool update_watch) {
   if(!g_z_valid) return;
   if(g_bar_changed || SetActive()) {
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
      g_bar_changed = false;
      if(SetActive()) return;
   }
   if(update_watch) {
      WatchUpdate(g_wsell, -1, g_z_reg, g_z_sma, now_msc, bid, ask, ZFloat(-1, g_bar0_fz));
      WatchUpdate(g_wbuy,   1, g_z_reg, g_z_sma, now_msc, bid, ask, ZFloat( 1, g_bar0_fz));
   }
   if(WatchReady(g_wsell, now_msc))     LiveFire(-1, ts, bid, ask);
   else if(WatchReady(g_wbuy, now_msc)) LiveFire( 1, ts, bid, ask);
}

bool IsOurDeal(ulong deal, long entry) {
   return (HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagic && HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol &&
           HistoryDealGetInteger(deal, DEAL_ENTRY) == entry);
}

// ลบออเดอร์รอทั้งหมดของ EA (why = เหตุผลสำหรับ log)
void DeletePendings(string why) {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder()) continue;
      if(trade.OrderDelete(ticket)) PrintFormat("🗑️ ยกเลิกออเดอร์รอ #%I64u (%s)", ticket, why);
      else PrintFormat("❌ ยกเลิกออเดอร์รอ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

void CloseAllPositions() {
   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   DeletePendings("ก่อนตลาดปิดสัปดาห์");
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      if(trade.PositionClose(ticket))
         PrintFormat("🛑 ปิดไม้ #%I64u ก่อนตลาดปิดสัปดาห์", ticket);
      else
         PrintFormat("❌ ปิดไม้ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

// เวลาตัดจบของไม้ที่เปิดเวลา opened: ปิดแท่งที่ InpExitBars หลังแท่งที่ถูกเกี่ยว (= เวลาเปิดของแท่งถัดไป)
datetime ExitTimeOf(datetime opened) {
   return BarStartOf(opened) + (datetime)((long)(InpExitBars + 1) * PeriodSeconds(InpZ_Timeframe));
}

// เรียกทุก Tick และทุก 1 วินาที:
//   1) ออเดอร์รอ: จบแท่งที่วาง / เข้าช่วงห้ามเข้า (ก่อนปิดสัปดาห์ / ตลาดปิด) → ยกเลิก
//   2) ไม้ที่ถือ: ถึงเวลาตัดจบ → ปิดที่ราคาตลาด
void ManageOrders(datetime now, int ts) {
   if(now < g_ord_retry) return;
   long per = PeriodSeconds(InpZ_Timeframe);
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder()) continue;
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      bool     bar_end = (now >= BarStartOf(setup) + (datetime)per);
      if(!bar_end && ts != TS_WAIT_CLOSE && ts != TS_CLOSING) continue;
      if(trade.OrderDelete(ticket))
         PrintFormat("🗑️ ยกเลิกออเดอร์รอ #%I64u (%s)", ticket, (bar_end ? "จบแท่งแล้วยังไม่ถูกเกี่ยว" : "ช่วงห้ามเข้าก่อนปิดสัปดาห์"));
      else {
         g_ord_retry = now + 1;
         PrintFormat("❌ ยกเลิกออเดอร์รอ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(now < ExitTimeOf(opened)) continue;
      double prof = PositionGetDouble(POSITION_PROFIT);
      string kind = KindFromComment(PositionGetString(POSITION_COMMENT));
      if(trade.PositionClose(ticket)) {
         g_last_status = StringFormat("⏱️ ตัดจบ #%I64u (%s) ครบ %d แท่งหลังแท่งที่ถูกเกี่ยว | $%+.2f", ticket, kind, InpExitBars, prof);
         Print(g_last_status);
      } else {
         g_ord_retry = now + 1;
         PrintFormat("❌ ตัดจบ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

//====================================================================
// ⏱️ สถิติ tick ของแท่ง (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//   1) ความเร็ว: เริ่มจับเมื่อ Z ตัดขึ้นผ่าน InpSpeedFromZ ครั้งล่าสุดในแท่ง → วินาทีที่แตะ T2 / T3 / T4 ครั้งแรก
//      แยก Z_reg / Z_SMA / รวม (Z ตัวใดก็ได้ = ตัวที่สูงกว่า), แท่งเปิดมาเกินอยู่แล้ว = นับจากเวลาเปิดแท่ง (star)
//   2) ค้างโซน: เวลาที่ Z ตัวใดตัวหนึ่ง ≥ InpZoneZ (รวมในแท่ง / ต่อเนื่องนานสุด / ต่อเนื่องจนถึงตอนนี้)
//   3) K2: จำนวนครั้งที่ราคาทำยอดใหม่ของแท่ง ภายใน InpK2_Window_Sec ก่อนยอดล่าสุด (กระชาก = ทำยอดใหม่ถี่)
//   4) ยอดราคา + การถอยหลังยอด (ใช้หาผลสวนกลับ / พุ่งต่อของ CSV แท่ง)
//====================================================================
double SpeedLevel(int k) { return (k == 0) ? InpT2_Z : (k == 1 ? InpT3_Z : InpT4_Z); }

void SpeedReset(ZSpeed &sp) {
   sp.start = 0; sp.star = false; sp.above = false; sp.seen = false; sp.z0 = 0.0;
   for(int k = 0; k < 3; k++) { sp.sec[k] = -1; sp.star_k[k] = false; }
}

void SideStatReset(SideStat &st) {
   for(int i = 0; i < 3; i++) SpeedReset(st.sp[i]);
   st.peak_z = -99.0; st.zone_cum_ms = 0; st.zone_max_ms = 0; st.k2 = 0; st.k2_max = 0;
   st.ext_px = 0.0; st.ext_msc = 0; st.ext_sd = 0.0; st.back_px = 0.0; st.rev_msc = 0;
}

void BarSpeedReset(BarSpeed &b, datetime bar) {
   b.bar   = bar;
   b.fresh = false;
   for(int s = 0; s < 2; s++) SideStatReset(b.sd[s]);
}

void TrackerReset(SpeedTracker &k) {
   BarSpeedReset(k.cur, 0);
   BarSpeedReset(k.closed, 0);
   k.closed_new = false;
   k.last_msc   = 0;
   for(int s = 0; s < 2; s++) { k.tr[s].in_zone = false; k.tr[s].zone_from = 0; k.tr[s].head = 0; k.tr[s].cnt = 0; }
}

// a = Z ในทิศของการกระชากของฝั่งนี้, fresh = เห็น tick ตั้งแต่เปิดแท่ง (ไม่ใช่เริ่มกลางแท่ง)
void SpeedTick(ZSpeed &sp, double a, long msc, long open_msc, bool fresh) {
   bool up = (a >= InpSpeedFromZ);
   if(!sp.seen) {
      sp.seen  = true;
      sp.above = up;
      if(up && fresh) { sp.start = open_msc; sp.star = true; sp.z0 = a; }   // เริ่มกลางแท่งแล้วอยู่เหนือจุดเริ่ม = ไม่รู้จุดเริ่ม (รอตัดขึ้นใหม่)
   }
   else if(up && !sp.above) { sp.start = msc; sp.star = false; sp.above = true; sp.z0 = a; }
   else if(!up) sp.above = false;
   if(sp.start <= 0) return;
   for(int k = 0; k < 3; k++)
      if(sp.sec[k] < 0 && SpeedLevel(k) > InpSpeedFromZ && a > SpeedLevel(k)) {
         sp.sec[k]    = (int)((msc - sp.start) / 1000);
         sp.star_k[k] = sp.star;
      }
}

// อัตราพุ่ง (Z / วินาที) จากจุดเริ่มถึงเกณฑ์ k (−1 = ยังไม่ถึง)
double SpeedRate(const ZSpeed &sp, int k) {
   if(sp.sec[k] < 0) return -1.0;
   return (SpeedLevel(k) - sp.z0) / MathMax(1, sp.sec[k]);
}

// tick หนึ่งของฝั่งหนึ่ง: g = +1 SELL / −1 BUY, prev_msc = เวลา tick ก่อนหน้า
void SideTick(SideStat &st, SideTrack &tr, double g, double zr, double zs, double bid, double sd,
              long msc, long open_msc, long prev_msc, bool fresh) {
   double ar = g * zr, as = g * zs, ac = MathMax(ar, as);
   SpeedTick(st.sp[0], ar, msc, open_msc, fresh);
   SpeedTick(st.sp[1], as, msc, open_msc, fresh);
   SpeedTick(st.sp[2], ac, msc, open_msc, fresh);
   if(ac > st.peak_z) st.peak_z = ac;

   // ค้างโซน: ช่วงเวลาตั้งแต่ tick ก่อนหน้าถึง tick นี้นับเป็น "ในโซน" ถ้า tick ก่อนหน้าอยู่ในโซน
   if(tr.in_zone && prev_msc > 0) {
      long from = MathMax(prev_msc, open_msc);
      if(msc > from) st.zone_cum_ms += msc - from;
   }
   bool inz = (ac >= InpZoneZ);
   if(inz && !tr.in_zone) tr.zone_from = msc;
   tr.in_zone = inz;
   if(inz) st.zone_max_ms = MathMax(st.zone_max_ms, msc - MathMax(tr.zone_from, open_msc));

   // ยอดราคาของแท่ง + K2 (เวลาที่ทำยอดใหม่ เก็บในวงแหวน ตัดอันที่เก่ากว่าหน้าต่างทิ้ง)
   bool new_ext = (st.ext_px <= 0.0) || (g > 0.0 ? bid > st.ext_px : bid < st.ext_px);
   if(new_ext) {
      st.ext_px = bid; st.ext_msc = msc; st.ext_sd = sd; st.back_px = bid; st.rev_msc = 0;
      tr.ring[(tr.head + tr.cnt) % K2_RING] = msc;
      if(tr.cnt < K2_RING) tr.cnt++;
      else tr.head = (tr.head + 1) % K2_RING;
      long win = (long)InpK2_Window_Sec * 1000;
      while(tr.cnt > 0 && tr.ring[tr.head] < msc - win) { tr.head = (tr.head + 1) % K2_RING; tr.cnt--; }
      st.k2 = tr.cnt;
      if(tr.cnt > st.k2_max) st.k2_max = tr.cnt;
   }
   else {
      if(g > 0.0 ? bid < st.back_px : bid > st.back_px) st.back_px = bid;
      if(st.rev_msc == 0 && st.ext_sd > 0.0 && g * (st.ext_px - bid) >= InpOutcomeSigma * st.ext_sd) st.rev_msc = msc;
   }
}

// อัปเดตตัวติดตามด้วย tick หนึ่ง (zr / zs = Z สด, sd = SD20) — ขึ้นแท่งใหม่ → เก็บแท่งเดิมลงประวัติ + closed_new
void TrackTick(SpeedTracker &k, double zr, double zs, double bid, double sd, long msc) {
   k.closed_new = false;
   datetime bar = BarStartOf((datetime)(msc / 1000));
   if(bar != k.cur.bar) {
      bool fresh = (k.cur.bar != 0);   // เห็นแท่งก่อนหน้าแล้ว = tick แรกของแท่งนี้คือต้นแท่ง
      if(k.cur.bar != 0) { SpeedStore(k.cur); k.closed = k.cur; k.closed_new = true; }
      BarSpeedReset(k.cur, bar);
      k.cur.fresh = fresh;
      for(int s = 0; s < 2; s++) { k.tr[s].head = 0; k.tr[s].cnt = 0; }   // K2 นับยอดใหม่ของแท่งนี้
   }
   long open_msc = (long)bar * 1000;
   SideTick(k.cur.sd[0], k.tr[0],  1.0, zr, zs, bid, sd, msc, open_msc, k.last_msc, k.cur.fresh);
   SideTick(k.cur.sd[1], k.tr[1], -1.0, zr, zs, bid, sd, msc, open_msc, k.last_msc, k.cur.fresh);
   k.last_msc = msc;
}

// ค้างโซนต่อเนื่องจนถึงเวลา msc (วินาที, 0 = ไม่ได้อยู่ในโซน) — นับข้ามแท่งได้
long ZoneRunSec(const SideTrack &tr, long msc) {
   return tr.in_zone ? (msc - tr.zone_from) / 1000 : 0;
}

int SpeedFind(datetime bar) {
   int lo = 0, hi = ArraySize(g_spd_hist) - 1;
   while(lo <= hi) {
      int mid = (lo + hi) / 2;
      if(g_spd_hist[mid].bar == bar) return mid;
      if(g_spd_hist[mid].bar < bar) lo = mid + 1; else hi = mid - 1;
   }
   return -1;
}

// เก็บสถิติของแท่ง (เรียงตามเวลา, แท่งเดิม = เขียนทับ, เกิน SPEED_KEEP แท่ง = ลบเก่าสุด)
void SpeedStore(const BarSpeed &b) {
   int k = SpeedFind(b.bar);
   if(k >= 0) { g_spd_hist[k] = b; return; }
   int n = ArraySize(g_spd_hist);
   ArrayResize(g_spd_hist, n + 1, 256);
   int i = n;
   while(i > 0 && g_spd_hist[i - 1].bar > b.bar) { g_spd_hist[i] = g_spd_hist[i - 1]; i--; }
   g_spd_hist[i] = b;
   if(n + 1 > SPEED_KEEP) {
      int drop = n + 1 - SPEED_KEEP;
      for(int j = drop; j < n + 1; j++) g_spd_hist[j - drop] = g_spd_hist[j];
      ArrayResize(g_spd_hist, SPEED_KEEP);
   }
}

// สถิติ tick ของแท่งเวลา bar — false = ไม่มีข้อมูล tick ของแท่งนี้ (เก่ากว่าช่วง Tick Replay)
bool SpeedOf(datetime bar, BarSpeed &b) {
   if(bar == 0) return false;
   if(bar == g_trk_live.cur.bar && g_trk_live.cur.fresh) { b = g_trk_live.cur; return true; }
   if(bar == g_trk_rp.cur.bar) { b = g_trk_rp.cur; return true; }         // Tick Replay เดินต่อแบบสดถึงแท่งปัจจุบัน
   if(bar == g_trk_live.cur.bar) { b = g_trk_live.cur; return true; }     // EA เริ่มกลางแท่ง (นับเฉพาะหลังเริ่ม)
   int k = SpeedFind(bar);
   if(k < 0) return false;
   b = g_spd_hist[k];
   return true;
}

// เวลาแบบสั้น: 45วิ / 3น.10 / 2ชม.05
string ShortSec(long sec) {
   if(sec < 0)    sec = 0;
   if(sec < 60)   return StringFormat("%dวิ", (int)sec);
   if(sec < 3600) return StringFormat("%dน.%02d", (int)(sec / 60), (int)(sec % 60));
   return StringFormat("%dชม.%02d", (int)(sec / 3600), (int)((sec % 3600) / 60));
}

// "12วิ" / "12วิ*" / "−" (ยังไม่ถึง / ไม่รู้)
string SpeedCell(const ZSpeed &sp, int k) {
   if(sp.sec[k] < 0) return "−";
   return ShortSec(sp.sec[k]) + (sp.star_k[k] ? "*" : "");
}

// "2.5: 12วิ | 3.0: 20วิ* | 3.5: −"
string SpeedLong(const ZSpeed &sp) {
   string s = "";
   for(int k = 0; k < 3; k++) {
      if(k > 0) s += " | ";
      s += DoubleToString(SpeedLevel(k), 1) + ": " + SpeedCell(sp, k);
   }
   return s;
}

//====================================================================
// ▮ แท่งติดกันในโซน (จาก OHLC — คำนวณได้ทุกแท่งย้อนหลัง ไม่ต้องใช้ tick)
//====================================================================
// Z ของแท่ง j ที่ราคาเปิด / สูง / ต่ำ / ปิด → zr[4], zs[4] (0 O, 1 H, 2 L, 3 C)
bool BarZOHLC(const MqlRates &r[], const double &c[], int j, double &zr[], double &zs[]) {
   double px[4];
   px[0] = r[j].open; px[1] = r[j].high; px[2] = r[j].low; px[3] = r[j].close;
   for(int q = 0; q < 4; q++) if(!ZForBarPrice(c, j, px[q], zr[q], zs[q])) return false;
   return true;
}

// แท่งติดกันจนถึงแท่ง j (รวมแท่ง j) ที่ Z ตัวใดตัวหนึ่ง (ทิศของฝั่ง) ≥ InpZoneZ — ที่ยอดแท่ง / ที่ราคาปิด
void ZStreaks(const MqlRates &r[], const double &c[], int j, int side, int &peak_n, int &close_n) {
   peak_n = 0; close_n = 0;
   double g  = (side == 0) ? 1.0 : -1.0;
   bool   pk = true, cl = true;
   for(int q = j; q >= InpZ_Period - 1 && q > j - STREAK_MAX && (pk || cl); q--) {
      double zr, zs;
      if(pk) {
         if(ZForBarPrice(c, q, (side == 0) ? r[q].high : r[q].low, zr, zs) && MathMax(g * zr, g * zs) >= InpZoneZ) peak_n++;
         else pk = false;
      }
      if(cl) {
         if(ZForBarPrice(c, q, r[q].close, zr, zs) && MathMax(g * zr, g * zs) >= InpZoneZ) close_n++;
         else cl = false;
      }
   }
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

// ตั้งข้อความวัตถุ — ข้อความเปลี่ยน = ต้องจัดตำแหน่งป้ายใหม่
void SetLabelText(string name, string text) {
   if(ObjectGetString(0, name, OBJPROP_TEXT) == text) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   g_lbl_ver++;
}

void DeleteLabel(string name) {
   if(ObjectFind(0, name) < 0) return;
   ObjectDelete(0, name);
   g_lbl_ver++;
}

// สร้างป้ายข้อความบนแท่ง (ตำแหน่งราคาจริงจัดโดย LayoutLabels)
void EnsureBarText(string name, datetime t, double price, bool up, color clr, bool bold) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, ND(price));
      ObjectSetString(0,  name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, up ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      RememberBarZLabel(name, t);
      g_lbl_ver++;
   }
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != clr) ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

// แถวที่ 2 ของป้าย: "เร็ว 12วิ · ค้าง 45วิ · K2 7 · ติด 2"
string BarInfoText(const BarView &v, int side, bool has, const SideStat &st) {
   string s = "";
   if(has) {
      if(st.sp[2].sec[0] >= 0) s += "เร็ว " + SpeedCell(st.sp[2], 0);
      if(st.zone_max_ms > 0)   s += (s == "" ? "" : " · ") + "ค้าง " + ShortSec(st.zone_max_ms / 1000);
      if(st.k2 > 0)            s += (s == "" ? "" : " · ") + "K2 " + IntegerToString(st.k2);
   }
   if(v.peak_n[side] >= 2)     s += (s == "" ? "" : " · ") + "ติด " + IntegerToString(v.peak_n[side]);
   return s;
}

// วาด/ลบป้าย Z ของแท่ง — แถว 1 (ติดแท่ง): Z_reg / Z_SMA / Z_float, แถว 2: เร็ว / ค้าง / K2 / แท่งติดกัน
void SetBarZLabels(const BarView &v) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)v.t);
   BarSpeed bs;
   bool   has = InpShowZSpeed && SpeedOf(v.t, bs);

   for(int side = 0; side < 2; side++) {
      string name = OBJ_PREFIX + (side == 0 ? "ZL_S_" : "ZL_B_") + ts;
      string info = OBJ_PREFIX + (side == 0 ? "ZM_S_" : "ZM_B_") + ts;
      bool   hit_r, hit_s;
      if(side == 0) { hit_r = v.zr[0] > InpT2_Z;  hit_s = v.zs[0] > InpT2_Z; }
      else          { hit_r = v.zr[1] < -InpT2_Z; hit_s = v.zs[1] < -InpT2_Z; }
      bool show = v.ok[side] && (hit_r || hit_s);
      if(!show) { DeleteLabel(name); DeleteLabel(info); continue; }

      int    dir        = (side == 0) ? -1 : 1;
      double zf_side    = ZFloat(dir, v.fz);
      int    tier       = TierOf(dir, v.zr[side], v.zs[side], zf_side);
      bool   hit_active = (tier >= 1);
      color  clr   = !hit_active ? InpClrBarZOther : (side == 0 ? InpClrBarZSell : InpClrBarZBuy);
      double price = (side == 0) ? (v.hi + off) : (v.lo - off);
      EnsureBarText(name, v.t, price, side == 0, clr, true);
      SetLabelText(name, StringFormat("R%+.2f  S%+.2f  F%+.1f", v.zr[side], v.zs[side], zf_side));

      string tip = StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s | Z_float %+.2f | %s",
                                TimeToString(v.t, TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                v.zr[side], (hit_r ? " ✓" : ""), v.zs[side], (hit_s ? " ✓" : ""), zf_side,
                                (hit_active ? "ถึงระดับ " + StageTag(tier) : "ถึงเกณฑ์ไม่ครบ"));
      SideStat st;
      if(has) st = bs.sd[side];
      else    SideStatReset(st);
      if(has)
         tip += StringFormat("\nเร็ว (Z ตัวใดก็ได้ จาก %.1f) → %s\nค้าง Z ≥ %.1f: นานสุด %s / รวม %s | K2 %d (สูงสุด %d)",
                             InpSpeedFromZ, SpeedLong(st.sp[2]), InpZoneZ, ShortSec(st.zone_max_ms / 1000),
                             ShortSec(st.zone_cum_ms / 1000), st.k2, st.k2_max);
      tip += StringFormat("\nแท่งติดกันที่ยอด Z ≥ %.1f: %d | ชี้เมาส์ที่แท่งเพื่อดูรายละเอียดทั้งหมด (มุมซ้ายล่าง)", InpZoneZ, v.peak_n[side]);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);

      string itx = InpShowZSpeed ? BarInfoText(v, side, has, st) : "";
      if(itx == "") { DeleteLabel(info); continue; }
      EnsureBarText(info, v.t, price, side == 0, InpClrBarZInfo, false);
      SetLabelText(info, itx);
      ObjectSetString(0, info, OBJPROP_TOOLTIP, tip);
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
      if(!show) { DeleteLabel(name); continue; }
      double price = (side == 0) ? (lo - off) : (hi + off);
      EnsureBarText(name, t, price, side == 1, hit ? InpClrFloatMark : InpClrBarZOther, true);
      SetLabelText(name, StringFormat("F%+.2f", zf));
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
   int cnt = bars + n - 1 + STREAK_MAX;
   MqlRates r[];
   double   c[];
   int got = CopyRates(_Symbol, InpZ_Timeframe, from_shift, cnt, r);
   if(got < n + 1) return;
   ArrayResize(c, got);
   for(int i = 0; i < got; i++) c[i] = r[i].close;

   int pk_run[2];
   int cl_run[2];
   ArrayInitialize(pk_run, 0);
   ArrayInitialize(cl_run, 0);
   for(int j = n - 1; j < got; j++) {
      BarView v;
      v.t = r[j].time; v.hi = r[j].high; v.lo = r[j].low; v.open = r[j].open;
      v.ok[0] = ZForBarPrice(c, j, r[j].high, v.zr[0], v.zs[0]);
      v.ok[1] = ZForBarPrice(c, j, r[j].low,  v.zr[1], v.zs[1]);
      double zcr = 0.0, zcs = 0.0;
      bool   cok = ZForBarPrice(c, j, r[j].close, zcr, zcs);
      for(int s = 0; s < 2; s++) {   // แท่งติดกัน (นับต่อเนื่องตั้งแต่ต้นชุดข้อมูล)
         double g  = (s == 0) ? 1.0 : -1.0;
         bool   pk = v.ok[s] && MathMax(g * v.zr[s], g * v.zs[s]) >= InpZoneZ;
         bool   cl = cok && MathMax(g * zcr, g * zcs) >= InpZoneZ;
         pk_run[s]   = pk ? pk_run[s] + 1 : 0;
         cl_run[s]   = cl ? cl_run[s] + 1 : 0;
         v.peak_n[s] = pk_run[s];
      }
      if(j < got - bars) continue;   // แท่งที่ใช้นับย้อนหลังเท่านั้น
      double sma = 0.0, sd = 0.0;
      bool   fok = SmaSdAt(c, j, r[j].open, sma, sd);
      v.fz = fok ? (r[j].open - sma) / sd : 0.0;
      if(InpShowBarZ) SetBarZLabels(v);
      if(fok) SetBarFloatLabel(v.t, v.hi, v.lo, v.open, sma, sd, false);
   }
   if(from_shift == 1)   // จำแท่งติดกันจนถึงแท่งที่ปิดล่าสุด (ใช้ต่อกับแท่งปัจจุบัน)
      for(int s = 0; s < 2; s++) { g_prev_pk[s] = pk_run[s]; g_prev_cl[s] = cl_run[s]; }
}

// ลบป้ายของแท่งที่เก่ากว่าช่วงที่แสดง
void PruneBarZLabels() {
   datetime cutoff = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(cutoff == 0) return;
   int n = ArraySize(g_zl_names), w = 0;
   for(int i = 0; i < n; i++) {
      if(g_zl_times[i] < cutoff || ObjectFind(0, g_zl_names[i]) < 0) {
         ObjectDelete(0, g_zl_names[i]);
         g_lbl_ver++;
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

   // แท่งปัจจุบัน: ใช้แคช Z สด + High/Low ที่ติดตามไว้, แท่งติดกัน = แท่งที่ปิดแล้ว + แท่งนี้ (ถ้ายอดถึงโซน)
   BarView v;
   v.t = t0; v.hi = g_bar0_hi; v.lo = g_bar0_lo; v.open = g_bar0_open; v.fz = g_bar0_fz;
   double px[2];
   px[0] = g_bar0_hi;
   px[1] = g_bar0_lo;
   for(int s = 0; s < 2; s++) {
      double fit, sig, mn, ssd;
      bool   fl;
      v.zr[s] = 0.0; v.zs[s] = 0.0;
      v.ok[s] = (px[s] > 0.0) && ZAtPrice(g_zc, px[s], v.zr[s], v.zs[s], fit, sig, fl, mn, ssd);
      double g = (s == 0) ? 1.0 : -1.0;
      v.peak_n[s] = (v.ok[s] && MathMax(g * v.zr[s], g * v.zs[s]) >= InpZoneZ) ? g_prev_pk[s] + 1 : 0;
   }
   if(InpShowBarZ) SetBarZLabels(v);
   SetBarFloatLabel(t0, g_bar0_hi, g_bar0_lo, g_bar0_open, g_bar0_fsma, g_bar0_fsd, InpFloatMarkLive);   // แท่งปัจจุบัน: ค่าตอนเปิดแท่ง (คงที่)
}

//====================================================================
// 🟨 TF ใหญ่ (InpHTF, ค่าเริ่มต้น M30): แท่งที่ Z ถึง T2-T4 ตามกฎเดียวกับ EA (รวมแท่งลอย + ปุ่ม T2-T4)
//   Z ของแท่ง TF ใหญ่ที่ High (SELL) / Low (BUY) จากราคาปิด 19 แท่ง TF ใหญ่ก่อนหน้า → กรอบเส้นประ + ป้าย "M30 T3"
//   แท่งที่กำลังเดิน: แสดงทันทีที่แตะ (High / Low ขยายได้ทางเดียว → ระดับขึ้นได้อย่างเดียว)
//====================================================================
string HTFName() { return StringSubstr(EnumToString(InpHTF), 7); }

color HTFColor(int tier) {
   if(tier >= 4) return InpClrHTF4;
   if(tier == 3) return InpClrHTF3;
   return InpClrHTF2;
}

// ระดับของแท่ง TF ใหญ่ j ที่ราคา px ฝั่ง side (c = ราคาปิด TF ใหญ่, open = ราคาเปิดแท่ง) → zr / zs ที่ราคานั้น
int HTFTierOf(const double &c[], int j, double open, double px, int side, double &zr, double &zs) {
   zr = 0.0; zs = 0.0;
   if(!ZForBarPrice(c, j, px, zr, zs)) return 0;
   double sma = 0.0, sd = 0.0;
   double fz  = SmaSdAt(c, j, open, sma, sd) ? (open - sma) / sd : 0.0;
   int    dir = (side == 0) ? -1 : 1;
   return TierOf(dir, zr, zs, ZFloat(dir, fz));
}

// ระดับของแท่ง TF ใหญ่ที่ครอบเวลา t ทั้งแท่ง (แท่งที่กำลังเดิน = ถึงตอนนี้) — ใช้แสดงผล
int HTFTierAt(datetime t, int side, double &zr, double &zs, datetime &hbar) {
   zr = 0.0; zs = 0.0; hbar = 0;
   if(!g_htf_ok) return 0;
   int sh = iBarShift(_Symbol, InpHTF, t, false);
   if(sh < 0) return 0;
   MqlRates r[];
   int got = CopyRates(_Symbol, InpHTF, sh, InpZ_Period + 1, r);
   if(got < InpZ_Period + 1) return 0;
   double c[];
   ArrayResize(c, got);
   for(int i = 0; i < got; i++) c[i] = r[i].close;
   int j = got - 1;
   hbar = r[j].time;
   return HTFTierOf(c, j, r[j].open, (side == 0) ? r[j].high : r[j].low, side, zr, zs);
}

// วาด / ลบกรอบ + ป้ายของแท่ง TF ใหญ่ j
void DrawHTFMark(const MqlRates &r[], const double &c[], int j) {
   double zru, zsu, zrd, zsd;
   int    tu = HTFTierOf(c, j, r[j].open, r[j].high, 0, zru, zsu);
   int    td = HTFTierOf(c, j, r[j].open, r[j].low,  1, zrd, zsd);
   string ts = IntegerToString((long)r[j].time);
   string nr = OBJ_PREFIX + "HT_R_" + ts, nu = OBJ_PREFIX + "HT_U_" + ts, nd = OBJ_PREFIX + "HT_D_" + ts;
   int    tm = MathMax(tu, td);
   if(tm == 0) { DeleteLabel(nr); DeleteLabel(nu); DeleteLabel(nd); return; }

   long     per  = PeriodSeconds(InpHTF);
   datetime t1   = r[j].time + (datetime)per;
   datetime tmid = r[j].time + (datetime)(per / 2);
   string   tip  = StringFormat("%s %s | SELL (ที่ High): %s Z_reg %+.2f / Z_SMA %+.2f | BUY (ที่ Low): %s Z_reg %+.2f / Z_SMA %+.2f",
                                HTFName(), TimeToString(r[j].time, TIME_DATE|TIME_MINUTES),
                                (tu > 0 ? StageTag(tu) : "ไม่ถึง"), zru, zsu, (td > 0 ? StageTag(td) : "ไม่ถึง"), zrd, zsd);
   if(ObjectFind(0, nr) < 0) {
      ObjectCreate(0, nr, OBJ_RECTANGLE, 0, r[j].time, r[j].high, t1, r[j].low);
      ObjectSetInteger(0, nr, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nr, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nr, OBJPROP_FILL, false);
      ObjectSetInteger(0, nr, OBJPROP_BACK, true);
      ObjectSetInteger(0, nr, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nr, OBJPROP_HIDDEN, true);
      RememberBarZLabel(nr, r[j].time);
   }
   ObjectMove(0, nr, 0, r[j].time, r[j].high);
   ObjectMove(0, nr, 1, t1, r[j].low);
   ObjectSetInteger(0, nr, OBJPROP_COLOR, HTFColor(tm));
   ObjectSetString(0,  nr, OBJPROP_TOOLTIP, tip);

   double off = PtsToPrice(InpBarZOffset_Pts);
   if(tu > 0) {
      EnsureBarText(nu, tmid, r[j].high + off, true, HTFColor(tu), true);
      SetLabelText(nu, HTFName() + " " + StageTag(tu));
      ObjectSetString(0, nu, OBJPROP_TOOLTIP, tip);
   }
   else DeleteLabel(nu);
   if(td > 0) {
      EnsureBarText(nd, tmid, r[j].low - off, false, HTFColor(td), true);
      SetLabelText(nd, HTFName() + " " + StageTag(td));
      ObjectSetString(0, nd, OBJPROP_TOOLTIP, tip);
   }
   else DeleteLabel(nd);
}

// เรียกทุก 1 วินาที: ครั้งแรก = ย้อนหลังเท่าช่วงป้าย Z, ขึ้นแท่งใหม่ = แท่งที่เพิ่งปิด + แท่งใหม่, ปกติ = แท่งที่กำลังเดิน
void UpdateHTFMarks() {
   if(!g_draw || !InpShowHTF || !g_htf_ok) return;
   datetime h0 = iTime(_Symbol, InpHTF, 0);
   if(h0 == 0) return;
   int need = 1;
   if(g_htf_bar == 0)
      need = (int)MathMin(5000, MathMax(10, (long)InpBarZBars * PeriodSeconds(InpZ_Timeframe) / PeriodSeconds(InpHTF) + 1));
   else if(h0 != g_htf_bar) need = 2;
   MqlRates r[];
   int got = CopyRates(_Symbol, InpHTF, 0, need + InpZ_Period, r);
   if(got < InpZ_Period + 1) return;
   double c[];
   ArrayResize(c, got);
   for(int i = 0; i < got; i++) c[i] = r[i].close;
   for(int j = MathMax(InpZ_Period - 1, got - need); j < got; j++) DrawHTFMark(r, c, j);
   g_htf_bar = h0;
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
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("   %s%s %s | %s | ห่างไส้ %.0f", (tier_m > 0 ? StageTag(tier_m) + " " : ""), KindFromComment(m.cmt), (is_sell ? "S" : "B"),
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
//   (T2 5 วิ / T3 2 วิ / T4 ทันที / เวลาตลาด / สเปรด / ครั้งละ 1 ไม้ / TP / SL ยอด / เกราะ 2 ขั้น / โล่ / ปิดสุดสัปดาห์)
//====================================================================
#define RX_OPEN   0   // ถูกเกี่ยวแล้ว ถืออยู่
#define RX_TIME   1   // ตัดจบตามเวลา
#define RX_SL     2
#define RX_WEEK   3   // บังคับปิดก่อนตลาดปิดสัปดาห์
#define RX_PEND   4   // ออเดอร์รอ (ยังไม่ถูกเกี่ยว)
#define RX_EXP    5   // ไม่ถูกเกี่ยวจนจบแท่ง → ยกเลิก

// ไม้จำลอง 1 ขา (ชุดละ 2 ขา: kind 0 = สวนกลับ / 1 = ตามน้ำ)
struct RTrade {
   int      set_id;        // รหัสชุด (สัญญาณเดียวกัน)
   int      kind;          // 0 = สวน / 1 = ตาม
   int      sl_mode;       // ที่มาของ SL (SLM_*)
   int      sig_dir;       // ทิศของฝั่งสวน (−1 = สัญญาณ SELL จาก Z ขึ้น / +1 = สัญญาณ BUY)
   long     msc_sig;       // เวลาสัญญาณ (วางออเดอร์)
   double   p_order;       // ราคา Stop
   long     exp_msc;       // ยกเลิกถ้ายังไม่ถูกเกี่ยวเมื่อถึงเวลานี้ (จบแท่งสัญญาณ / ช่วงห้ามเข้าก่อนปิดสัปดาห์)
   long     exit_msc;      // ตัดจบตามเวลา (หลังถูกเกี่ยว)
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
   SideStat ss;                           // สถิติ tick ของแท่ง ณ ตอนยิง (ฝั่งนี้): ความเร็ว / ค้างโซน / K2
   bool     ss_ok;                        // มีข้อมูล tick ของแท่งนี้
   long     zone_run;                     // ค้าง Z ≥ InpZoneZ ต่อเนื่องจนถึงตอนยิง (วินาที, ข้ามแท่งได้)
   int      prev_pk, prev_cl;             // แท่งก่อนหน้าติดกันที่ยอด Z / Z ปิดแท่ง ≥ InpZoneZ
   double   zb[6];                        // Z ของแท่งจนถึงตอนยิง: Z_reg เปิด / สูง / ต่ำ, Z_SMA เปิด / สูง / ต่ำ
   int      htf_tier;                     // ระดับของแท่ง TF ใหญ่ (ฝั่งการกระชาก) ณ ตอนยิง (0 = ไม่ถึง)
   double   htf_zr, htf_zs;               // Z ของแท่ง TF ใหญ่ที่ยอดจนถึงตอนยิง
   // ระยะกำไรระหว่างถือ (ราคา): ต่ำสุด = mae, สูงสุด = mfe, เฉลี่ยถ่วงตามเวลา = pa_sum / pa_ms
   double   pa_sum, pa_ms, pa_fav;
   long     pa_msc;
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

// แท่งที่ Z ≥ InpZoneZ ใน Tick Replay + ผลภายใน InpOutcomeMin นาทีหลังยอดของแท่ง (CSV แท่ง)
#define BO_WAIT 0
#define BO_REV  1
#define BO_CONT 2
#define BO_UNC  3
struct BarRec {
   datetime bar;
   int      side;          // 0 = SELL (Z ขึ้น) / 1 = BUY (Z ลง)
   double   zr[4];         // Z_reg ของแท่งที่ เปิด / สูง / ต่ำ / ปิด (ค่าจริงมีเครื่องหมาย)
   double   zs[4];         // Z_SMA ของแท่งที่ เปิด / สูง / ต่ำ / ปิด
   double   fz;            // Z_float (+ = ราคาเปิดเหนือ SMA)
   SideStat st;
   bool     fresh;
   int      peak_n, close_n;
   int      result;
   long     res_msc;
   double   max_rev;       // ถอยจากยอดไกลสุด (σ)
   double   max_cont;      // ทะลุยอดไกลสุด (จุด)
   int      htf_tier;      // ระดับของแท่ง TF ใหญ่ ณ ตอนปิดแท่งนี้ (ไม่มองอนาคต)
   double   htf_zr, htf_zs;
};

RTrade     g_rt[];
RBlocked   g_rb[];
BarRec     g_bo[];
int        g_bo_first     = 0;       // แท่งแรกที่ยังรอผล
int        g_bo_csv_rows  = -1;
double     g_rrc[];                  // ราคาปิดของ g_rr (สำหรับ Z ที่ราคาใดๆ ของแท่ง)
MqlRates   g_rh[];                   // แท่ง TF ใหญ่ของช่วง Replay
double     g_rhc[];
bool       g_set_on       = false;   // มีชุดออเดอร์ที่ยังไม่จบ
int        g_set_leg[2];             // index ใน g_rt ของขาสวน / ขาตาม ของชุดปัจจุบัน
int        g_set_n        = 0;       // จำนวนชุดที่วางแล้ว (รหัสชุดถัดไป)
int        g_set_csv_rows = -1;
int        g_rb_drawn     = 0;

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
long       g_rp_fail_cur  = -1;      // ช่วงที่กำลังดึง tick ไม่สำเร็จ (cursor) / เริ่มไม่สำเร็จเมื่อ (GetTickCount)
uint       g_rp_fail_ms   = 0;
int        g_rp_skip_n    = 0;       // จำนวนช่วงที่ข้ามเพราะดึง tick ไม่สำเร็จเกิน RP_SKIP_SEC
string     g_rp_skip_txt  = "";
long       g_rp_ticks     = 0;
string     g_rp_status    = "ยังไม่เริ่ม";
double     g_contract     = 100.0;

void ReplayReset() {
   ArrayResize(g_rt, 0);
   ArrayResize(g_rb, 0);
   ArrayResize(g_rr, 0);
   g_set_on = false; g_set_leg[0] = -1; g_set_leg[1] = -1; g_set_n = 0; g_set_csv_rows = -1; g_rb_drawn = 0;
   TrackerReset(g_trk_rp);
   ArrayResize(g_bo, 0);
   g_bo_first = 0; g_bo_csv_rows = -1;
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false; g_rp_bar_chg = false; g_rp_hi = 0.0; g_rp_lo = 0.0;
   WatchReset(g_rp_ws); WatchReset(g_rp_wb);
   ArrayResize(g_tk_msc, 0); ArrayResize(g_tk_bid, 0); g_tk_head = 0;
   g_rp_csv_rows = -1;
   g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_zr = 0.0; g_rp_zs = 0.0;
   g_rp_msc = 0; g_rp_have = false; g_rp_init = false; g_rp_caught = false;
   g_rp_cursor = 0; g_rp_retry = 0; g_rp_ticks = 0;
   g_rp_fail_cur = -1; g_rp_fail_ms = 0; g_rp_skip_n = 0; g_rp_skip_txt = "";
   g_rp_status = "ยังไม่เริ่ม";
}

bool ReplayLoadRates() {
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int count   = (InpReplayDays + 4) * per_day + InpZ_Period + STREAK_MAX + 10;
   int got = CopyRates(_Symbol, InpZ_Timeframe, 0, count, g_rr);
   if(got <= InpZ_Period + 3) return false;
   ArrayResize(g_rrc, got);
   for(int i = 0; i < got; i++) g_rrc[i] = g_rr[i].close;
   if(g_htf_ok) {   // TF ใหญ่ (โหลดไม่ได้ = ค่า TF ใหญ่ใน CSV เป็น 0)
      int hc = (int)((InpReplayDays + 4) * DAY_SEC / PeriodSeconds(InpHTF)) + InpZ_Period + 10;
      int gh = CopyRates(_Symbol, InpHTF, 0, hc, g_rh);
      ArrayResize(g_rhc, MathMax(gh, 0));
      for(int i = 0; i < gh; i++) g_rhc[i] = g_rh[i].close;
   }
   return true;
}

// ระดับของแท่ง TF ใหญ่ที่ครอบแท่ง g_rr[jb] ณ เวลาที่แท่ง jb มี High / Low = hi_now / lo_now
//   ยอดของแท่ง TF ใหญ่ = แท่ง TF ของ Z ก่อนหน้าในแท่ง TF ใหญ่เดียวกัน + แท่ง jb (ไม่มองอนาคต)
int ReplayHTFTier(int side, int jb, double hi_now, double lo_now, double &zr, double &zs) {
   zr = 0.0; zs = 0.0;
   int nh = ArraySize(g_rh);
   if(!g_htf_ok || nh == 0 || jb < 0) return 0;
   datetime t = g_rr[jb].time;
   int lo = 0, hi = nh - 1, jh = -1;
   while(lo <= hi) {   // แท่ง TF ใหญ่สุดท้ายที่เริ่มไม่เกิน t
      int mid = (lo + hi) / 2;
      if(g_rh[mid].time <= t) { jh = mid; lo = mid + 1; } else hi = mid - 1;
   }
   if(jh < InpZ_Period - 1) return 0;
   datetime hs = g_rh[jh].time;
   double   hh = hi_now, ll = lo_now;
   for(int q = jb - 1; q >= 0 && g_rr[q].time >= hs; q--) { hh = MathMax(hh, g_rr[q].high); ll = MathMin(ll, g_rr[q].low); }
   return HTFTierOf(g_rhc, jh, g_rh[jh].open, (side == 0) ? hh : ll, side, zr, zs);
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

// เพิ่มขาออเดอร์รอของชุด: sig_dir = ทิศฝั่งสวน, kind 0 สวน (ทิศ sig_dir) / 1 ตาม (ทิศตรงข้าม)
//   ค่าตอนสัญญาณ (Z / สถิติแท่ง / TF ใหญ่ / ปัจจัย) บันทึกเหมือนกันทั้ง 2 ขา
int ReplayAddLeg(int sig_dir, int kind, int stage, long msc, double order_px, double sl, long exp_msc, int set_id) {
   int i = ArraySize(g_rt);
   ArrayResize(g_rt, i + 1, 256);
   int      dir = (kind == 0) ? sig_dir : -sig_dir;
   double   hi  = (g_rp_hi > 0.0) ? MathMax(g_rp_hi, g_rp_bid) : g_rp_bid;
   double   lo  = (g_rp_lo > 0.0) ? MathMin(g_rp_lo, g_rp_bid) : g_rp_bid;
   datetime bar = BarStartOf((datetime)(msc / 1000));
   if(dir == 1) sl = MathMin(sl, order_px - _Point);   // SL ต้องอยู่ฝั่งขาดทุนของราคาเข้า
   else         sl = MathMax(sl, order_px + _Point);
   g_rt[i].set_id   = set_id;
   g_rt[i].kind     = kind;
   g_rt[i].sl_mode  = (kind == 0) ? SLM_PEAK : SLM_OPEN;
   g_rt[i].sig_dir  = sig_dir;
   g_rt[i].msc_sig  = msc;
   g_rt[i].p_order  = order_px;
   g_rt[i].exp_msc  = exp_msc;
   g_rt[i].exit_msc = 0;
   g_rt[i].msc_in   = 0;
   g_rt[i].dir      = dir;
   g_rt[i].stage    = stage;
   g_rt[i].lot      = TierLot(stage);
   g_rt[i].max_tier = stage;
   g_rt[i].p_in     = 0.0;
   g_rt[i].sl       = sl;
   g_rt[i].peak     = (sig_dir == -1) ? hi : lo;
   g_rt[i].bar_seq  = 0;
   g_rt[i].tp       = 0.0;
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
   int side = (sig_dir == -1) ? 0 : 1;   // ฝั่งของการกระชาก (สัญญาณ SELL = Z ขึ้น)
   g_rt[i].ss_ok    = (g_trk_rp.cur.bar == bar);
   if(g_rt[i].ss_ok) g_rt[i].ss = g_trk_rp.cur.sd[side];
   else              SideStatReset(g_rt[i].ss);
   g_rt[i].zone_run = ZoneRunSec(g_trk_rp.tr[side], msc);
   g_rt[i].prev_pk  = 0; g_rt[i].prev_cl = 0;
   if(g_rp_b >= InpZ_Period) ZStreaks(g_rr, g_rrc, g_rp_b - 1, side, g_rt[i].prev_pk, g_rt[i].prev_cl);
   for(int q = 0; q < 6; q++) g_rt[i].zb[q] = 0.0;
   if(g_rp_b >= 0) {
      double px[3];
      px[0] = g_rr[g_rp_b].open; px[1] = hi; px[2] = lo;
      for(int q = 0; q < 3; q++) {
         double zr, zs, fit, sig, mn, ssd;
         bool   fl;
         if(ZAtPrice(g_rp_zc, px[q], zr, zs, fit, sig, fl, mn, ssd)) { g_rt[i].zb[q] = zr; g_rt[i].zb[q + 3] = zs; }
      }
   }
   g_rt[i].htf_tier = ReplayHTFTier(side, g_rp_b, hi, lo, g_rt[i].htf_zr, g_rt[i].htf_zs);
   g_rt[i].pa_sum = 0.0; g_rt[i].pa_ms = 0.0; g_rt[i].pa_fav = 0.0; g_rt[i].pa_msc = msc;
   g_rt[i].force_close = 0;
   g_rt[i].msc_out  = 0;
   g_rt[i].p_out    = 0.0;
   g_rt[i].reason   = RX_PEND;
   g_rt[i].pnl      = 0.0;
   g_rt[i].usd      = 0.0;
   g_rt[i].drawn_final = false;
   return i;
}

// ออเดอร์รอถูกเกี่ยว: ราคาของ tick ที่ชน (รวม gap) → ถือ + ตั้งเวลาตัดจบ / บังคับปิดสุดสัปดาห์
void ReplayFill(int i, long msc, double price) {
   datetime t   = (datetime)(msc / 1000);
   datetime bar = BarStartOf(t);
   int      seq = 1;
   for(int k = i - 1; k >= 0; k--) {
      if(g_rt[k].msc_in == 0) continue;
      if(BarStartOf((datetime)(g_rt[k].msc_in / 1000)) != bar) break;
      seq++;
   }
   g_rt[i].reason      = RX_OPEN;
   g_rt[i].msc_in      = msc;
   g_rt[i].p_in        = price;
   g_rt[i].bar_seq     = seq;
   g_rt[i].mfe = 0.0; g_rt[i].mae = 0.0;
   g_rt[i].pa_sum = 0.0; g_rt[i].pa_ms = 0.0; g_rt[i].pa_fav = 0.0; g_rt[i].pa_msc = msc;
   g_rt[i].force_close = ForceCloseTimeAt(t);
   g_rt[i].exit_msc    = (long)ExitTimeOf(t) * 1000;
   g_lbl_ver++;   // มีป้ายไม้ใหม่ → จัดตำแหน่งป้ายใหม่
}

bool RDone(int r) { return (r == RX_TIME || r == RX_SL || r == RX_WEEK); }

// ชุดจบ = ไม่เหลือขาที่รอ / ถือ → เริ่มหาสัญญาณใหม่
void ReplaySetCheck() {
   if(!g_set_on) return;
   for(int m = 0; m < 2; m++) {
      int i = g_set_leg[m];
      if(i >= 0 && (g_rt[i].reason == RX_PEND || g_rt[i].reason == RX_OPEN)) return;
   }
   g_set_on = false;
   g_set_leg[0] = -1; g_set_leg[1] = -1;
   WatchReset(g_rp_ws);
   WatchReset(g_rp_wb);
}

// ปิดไม้จำลอง 1 ขา (ชุดจบ → ReplaySetCheck)
void ReplayClose(int i, long msc_out, double price, int reason) {
   if(i < 0 || g_rt[i].reason != RX_OPEN) return;
   g_rt[i].msc_out = msc_out;
   g_rt[i].p_out   = price;
   g_rt[i].reason  = reason;
   double diff     = (g_rt[i].dir == -1) ? (g_rt[i].p_in - price) : (price - g_rt[i].p_in);
   g_rt[i].pnl     = PriceToPts(diff);
   g_rt[i].usd     = diff * g_rt[i].lot * g_contract;
   ProfitAvgAdd(i, msc_out, diff);
}

void ReplayFire(int dir, long fire_msc) {
   WatchState w;
   if(dir == -1) w = g_rp_ws; else w = g_rp_wb;
   datetime t   = (datetime)(fire_msc / 1000);
   int      tier = w.tier;
   string   why = EntryBlockReason(GetTimeStateAt(t), g_rp_bid, g_rp_ask);
   if(why != "") {
      int k = ArraySize(g_rb);
      ArrayResize(g_rb, k + 1);
      g_rb[k].msc = fire_msc; g_rb[k].dir = dir; g_rb[k].why = StageTag(tier) + ": " + why;
      g_rb[k].price = (dir == -1) ? g_rp_bid : g_rp_ask;
      if(dir == -1) WatchReset(g_rp_ws); else WatchReset(g_rp_wb);
      return;
   }
   // วางชุด: สวน (ทิศ dir) + ตาม (ทิศตรงข้าม) ห่างฝั่งละ InpStopDist_Pts, หมดอายุเมื่อจบแท่ง / เข้าช่วงห้ามเข้าก่อนปิดสัปดาห์
   double   hi   = (g_rp_hi > 0.0) ? MathMax(g_rp_hi, g_rp_bid) : g_rp_bid;
   double   lo   = (g_rp_lo > 0.0) ? MathMin(g_rp_lo, g_rp_bid) : g_rp_bid;
   double   dist = PtsToPrice(InpStopDist_Pts);
   long     exp_ms = ((long)BarStartOf(t) + PeriodSeconds(InpZ_Timeframe)) * 1000;
   datetime nc     = NoEntryStartAt(t);
   if(nc > 0) exp_ms = MathMin(exp_ms, (long)nc * 1000);
   double   open  = (g_rp_b >= 0) ? g_rr[g_rp_b].open : g_rp_bid;
   double   open1 = (g_rp_b >= 1) ? g_rr[g_rp_b - 1].open : 0.0;
   double   ec    = (dir == 1) ? g_rp_ask + dist : g_rp_bid - dist;   // ราคาเข้าของขาสวน / ขาตาม
   double   ef    = (dir == 1) ? g_rp_bid - dist : g_rp_ask + dist;
   int      mc, mf;
   double   slc   = CounterSL(dir, ec, hi, lo, mc);
   double   slf   = TrendSL(-dir, ef, open, open1, mf);
   int      set   = ++g_set_n;
   int      ic    = ReplayAddLeg(dir, 0, tier, fire_msc, ec, slc, exp_ms, set);
   int      itf   = ReplayAddLeg(dir, 1, tier, fire_msc, ef, slf, exp_ms, set);
   g_rt[ic].sl_mode  = mc;
   g_rt[itf].sl_mode = mf;
   int      legs[2];
   legs[0] = ic; legs[1] = itf;
   for(int m = 0; m < 2; m++) {
      int i = legs[m];
      g_rt[i].ext_r    = w.ext_r;
      g_rt[i].ext_s    = w.ext_s;
      g_rt[i].max_tier = w.max_tier;
      ReplaySignalFactors(i, w, dir);
   }
   g_set_on     = true;
   g_set_leg[0] = ic;
   g_set_leg[1] = itf;
   WatchReset(g_rp_ws);
   WatchReset(g_rp_wb);
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
   if(g_set_on) {   // ชุดยังไม่จบ: ออเดอร์รอหมดอายุ / บังคับปิดสุดสัปดาห์ (ราคาของ tick ก่อนหน้า) — ไม่หาสัญญาณใหม่
      for(int m = 0; m < 2; m++) {
         int i = g_set_leg[m];
         if(i < 0) continue;
         if(g_rt[i].reason == RX_PEND && msc >= g_rt[i].exp_msc) { g_rt[i].reason = RX_EXP; g_rt[i].msc_out = g_rt[i].exp_msc; }
         else if(g_rt[i].reason == RX_OPEN) {
            long wk = (g_rt[i].force_close > 0) ? (long)g_rt[i].force_close * 1000 : LONG_MAX;
            if(wk <= msc) ReplayClose(i, wk, (g_rt[i].dir == -1) ? g_rp_ask : g_rp_bid, RX_WEEK);
         }
      }
      ReplaySetCheck();
      return;
   }
   // ครบเวลาเฝ้า (ราคาของ tick ก่อนหน้า) → วางชุด
   if(WatchReady(g_rp_ws, msc))      ReplayFire(-1, MathMax(WatchDeadline(g_rp_ws), g_rp_msc));
   else if(WatchReady(g_rp_wb, msc)) ReplayFire( 1, MathMax(WatchDeadline(g_rp_wb), g_rp_msc));
}

// ขาของชุด ด้วยราคา tick ปัจจุบัน: ออเดอร์รอ → ถูกเกี่ยว (Buy Stop: Ask ≥ ราคา / Sell Stop: Bid ≤ ราคา, ได้ราคาของ tick)
//   ไม้ที่ถือ → SL / ตัดจบ (tick แรกของแท่งถัดจากแท่งที่ InpExitBars)

void ReplayManageTick(long msc, double bid, double ask) {
   for(int m = 0; m < 2; m++) {
      int i = g_set_leg[m];
      if(i < 0) continue;
      int d = g_rt[i].dir;
      if(g_rt[i].reason == RX_PEND) {
         bool hit = (d == 1) ? (ask >= g_rt[i].p_order) : (bid <= g_rt[i].p_order);
         if(!hit) continue;
         ReplayFill(i, msc, (d == 1) ? ask : bid);
      }
      if(g_rt[i].reason != RX_OPEN) continue;
      double fav = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
      if(fav > g_rt[i].mfe) g_rt[i].mfe = fav;
      if(fav < g_rt[i].mae) g_rt[i].mae = fav;
      ProfitAvgAdd(i, msc, fav);
      double px = (d == -1) ? ask : bid;
      if(d == -1 ? (ask >= g_rt[i].sl) : (bid <= g_rt[i].sl)) { ReplayClose(i, msc, px, RX_SL);   continue; }
      if(msc >= g_rt[i].exit_msc)                               { ReplayClose(i, msc, px, RX_TIME); continue; }
   }
   ReplaySetCheck();
}

// แท่งเพิ่งปิด (Tick Replay): ฝั่งที่ Z ≥ InpZoneZ → บันทึกค่า OHLC Z / สถิติ tick / แท่งติดกัน แล้วรอผลหลังยอด
void ReplayBarClosed() {
   BarSpeed cb;
   cb = g_trk_rp.closed;
   int jb = -1;
   for(int j = MathMin(g_rp_b, ArraySize(g_rr) - 1); j >= 0; j--) {
      if(g_rr[j].time == cb.bar) { jb = j; break; }
      if(g_rr[j].time < cb.bar) break;
   }
   if(jb < InpZ_Period) return;
   for(int s = 0; s < 2; s++) {
      if(cb.sd[s].peak_z < InpZoneZ || cb.sd[s].ext_msc <= 0) continue;
      int k = ArraySize(g_bo);
      ArrayResize(g_bo, k + 1, 256);
      g_bo[k].bar   = cb.bar;
      g_bo[k].side  = s;
      g_bo[k].st    = cb.sd[s];
      g_bo[k].fresh = cb.fresh;
      double zr4[4];
      double zs4[4];
      bool   zok4 = BarZOHLC(g_rr, g_rrc, jb, zr4, zs4);
      for(int q = 0; q < 4; q++) { g_bo[k].zr[q] = zok4 ? zr4[q] : 0.0; g_bo[k].zs[q] = zok4 ? zs4[q] : 0.0; }
      double sma, sd;
      g_bo[k].fz = SmaSdAt(g_rrc, jb, g_rr[jb].open, sma, sd) ? (g_rr[jb].open - sma) / sd : 0.0;
      ZStreaks(g_rr, g_rrc, jb, s, g_bo[k].peak_n, g_bo[k].close_n);
      double g = (s == 0) ? 1.0 : -1.0;
      g_bo[k].max_rev  = (cb.sd[s].ext_sd > 0.0) ? g * (cb.sd[s].ext_px - cb.sd[s].back_px) / cb.sd[s].ext_sd : 0.0;
      g_bo[k].max_cont = 0.0;
      g_bo[k].htf_tier = ReplayHTFTier(s, jb, g_rr[jb].high, g_rr[jb].low, g_bo[k].htf_zr, g_bo[k].htf_zs);
      g_bo[k].result   = (cb.sd[s].rev_msc > 0) ? BO_REV : BO_WAIT;   // ถอยถึงเกณฑ์ตั้งแต่ในแท่ง
      g_bo[k].res_msc  = cb.sd[s].rev_msc;
   }
}

// ทุก tick: แท่งที่รอผล → ถอยจากยอด ≥ InpOutcomeSigma σ = สวนกลับ / ทะลุยอด ≥ InpSLPeak_Pts = พุ่งต่อ / ครบเวลา = ไม่ชัด
void ReplayOutcomeTick(long msc, double bid) {
   int n = ArraySize(g_bo);
   for(int k = g_bo_first; k < n; k++) {
      if(g_bo[k].result != BO_WAIT) { if(k == g_bo_first) g_bo_first++; continue; }
      double g  = (g_bo[k].side == 0) ? 1.0 : -1.0;
      long   dl = g_bo[k].st.ext_msc + (long)InpOutcomeMin * 60000;
      if(msc > dl) {
         g_bo[k].result = BO_UNC; g_bo[k].res_msc = dl;
         if(k == g_bo_first) g_bo_first++;
         continue;
      }
      double sd   = g_bo[k].st.ext_sd;
      double rev  = (sd > 0.0) ? g * (g_bo[k].st.ext_px - bid) / sd : 0.0;
      double cont = PriceToPts(g * (bid - g_bo[k].st.ext_px));
      if(rev  > g_bo[k].max_rev)  g_bo[k].max_rev  = rev;
      if(cont > g_bo[k].max_cont) g_bo[k].max_cont = cont;
      if(rev >= InpOutcomeSigma)        { g_bo[k].result = BO_REV;  g_bo[k].res_msc = msc; }
      else if(cont >= InpSLPeak_Pts)    { g_bo[k].result = BO_CONT; g_bo[k].res_msc = msc; }
   }
}

string BarResultCode(int r) {
   switch(r) {
      case BO_REV:  return "REV";
      case BO_CONT: return "CONT";
      case BO_UNC:  return "UNC";
   }
   return "WAIT";
}

int BarRecFind(datetime bar, int side) {
   for(int k = ArraySize(g_bo) - 1; k >= 0; k--) {
      if(g_bo[k].bar == bar && g_bo[k].side == side) return k;
      if(g_bo[k].bar < bar) break;
   }
   return -1;
}

string BarResultName(int r) {
   switch(r) {
      case BO_REV:  return "สวนกลับ";
      case BO_CONT: return "พุ่งต่อ";
      case BO_UNC:  return "ไม่ชัด";
   }
   return "รอผล";
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);

   ReplayTimeEvents(msc);                 // A) เหตุการณ์ตามเวลาด้วยราคาเดิม (ตัดเวลา / ยิงหลังครบเวลาเฝ้า)
   if(!ReplayBarFor(t)) return;           // B) แท่งของ tick นี้
   if(g_rp_hi <= 0.0 || bid > g_rp_hi) g_rp_hi = bid;
   if(g_rp_lo <= 0.0 || bid < g_rp_lo) g_rp_lo = bid;

   double zr = 0.0, zs = 0.0, fit, sig, mn, ssd;
   bool   fl;
   bool   zok = ZAtPrice(g_rp_zc, bid, zr, zs, fit, sig, fl, mn, ssd);
   if(zok) { g_rp_zr = zr; g_rp_zs = zs; g_rp_sma = g_rp_zc.ref + mn; g_rp_sd = ssd; g_rp_ctr = g_rp_zc.ref + fit; }
   if(zok) {   // สถิติ tick ของแท่ง (ก่อนยิง → ไม้ที่ยิงใน tick ถัดไปเห็นค่าล่าสุด)
      TrackTick(g_trk_rp, zr, zs, bid, ssd, msc);
      if(g_trk_rp.closed_new) ReplayBarClosed();
   }
   ReplayOutcomeTick(msc, bid);

   if(g_set_on) ReplayManageTick(msc, bid, ask);   // C) ชุดออเดอร์ (รอ / ถือ)

   // D) เฝ้าค่าสุดขั้ว: ขึ้นแท่งใหม่ / ชุดยังไม่จบ = ล้างการเฝ้า — เวลาตลาด / สเปรด ตรวจตอนวาง
   if(!zok || g_rp_bar_chg || g_set_on) { WatchReset(g_rp_ws); WatchReset(g_rp_wb); }
   if(zok && !g_set_on) {
      WatchUpdate(g_rp_ws, -1, zr, zs, msc, bid, ask, ZFloat(-1, g_rp_fz));
      WatchUpdate(g_rp_wb,  1, zr, zs, msc, bid, ask, ZFloat( 1, g_rp_fz));
   }
   g_rp_bar_chg = false;

   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc;
   g_rp_have = true;
   g_rp_ticks++;
   TickBufAdd(msc, bid);
}

string ReplayReasonName(int r) {
   switch(r) {
      case RX_TIME: return "ตัดจบ";
      case RX_SL:   return "SL";
      case RX_WEEK: return "ปิดสัปดาห์";
      case RX_PEND: return "รอ";
      case RX_EXP:  return "ไม่ถูกเกี่ยว";
   }
   return "ถืออยู่";
}

void DrawReplayTrade(int i) {
   bool     is_sell = (g_rt[i].dir == -1);
   string   kname   = (g_rt[i].kind == 0) ? "สวน" : "ตาม";
   string   tag     = StageTag(g_rt[i].stage);
   int      r       = g_rt[i].reason;
   bool     filled  = (g_rt[i].msc_in > 0);
   datetime t_sig   = (datetime)(g_rt[i].msc_sig / 1000);
   datetime t_in    = (datetime)(g_rt[i].msc_in / 1000);
   string   otype   = is_sell ? "SELL STOP" : "BUY STOP";
   string   slwhy   = SLModeText(g_rt[i].sl_mode);

   // 1) ระดับ Stop: เส้นจากเวลาสัญญาณ → ถูกเกี่ยว / หมดอายุ
   string   np    = OBJ_PREFIX + "RP_P_" + IntegerToString(g_rt[i].msc_sig) + "_" + IntegerToString(i);
   datetime t_end = filled ? t_in : (datetime)(((r == RX_EXP) ? g_rt[i].msc_out : g_rt[i].exp_msc) / 1000);
   color    pclr  = (r == RX_EXP) ? InpClrSimBlocked : ((g_rt[i].kind == 0) ? InpClrPendCounter : InpClrPendTrend);
   if(ObjectFind(0, np) < 0) {
      ObjectCreate(0, np, OBJ_TREND, 0, t_sig, g_rt[i].p_order, t_end, g_rt[i].p_order);
      ObjectSetInteger(0, np, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, np, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, np, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, np, OBJPROP_BACK, true);
      ObjectSetInteger(0, np, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, np, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, np, 1, t_end, g_rt[i].p_order);
   ObjectSetInteger(0, np, OBJPROP_COLOR, pclr);
   string ptip = StringFormat("ชุด #%d %s | %s %s %.2f lot @ %s | SL %s (%s) | วาง %s | %s",
                              g_rt[i].set_id, tag, kname, otype, g_rt[i].lot, DoubleToString(g_rt[i].p_order, _Digits),
                              DoubleToString(g_rt[i].sl0, _Digits), slwhy, TimeToString(t_sig, TIME_DATE|TIME_SECONDS),
                              filled ? "ถูกเกี่ยว " + TimeToString(t_in, TIME_SECONDS) : ReplayReasonName(r));
   ObjectSetString(0, np, OBJPROP_TOOLTIP, ptip);
   if(!filled) {
      g_rt[i].drawn_final = (r == RX_EXP && iBarShift(_Symbol, InpZ_Timeframe, t_sig, false) > 0);
      return;
   }

   // 2) ขาที่ถูกเกี่ยว: ลูกศรจุดเข้า + เส้นเข้า→ออก + ป้าย
   string id    = IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
   int    shift = iBarShift(_Symbol, InpZ_Timeframe, t_in, false);
   bool   open  = (r == RX_OPEN);
   color  clr   = is_sell ? InpClrSimSell : InpClrSimBuy;
   string na = OBJ_PREFIX + "RP_A_" + id, nl = OBJ_PREFIX + "RP_L_" + id, nt = OBJ_PREFIX + "RP_T_" + id;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, t_in, g_rt[i].p_in);
      ObjectSetInteger(0, na, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
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
                   open ? StringFormat("%s %s %s %.2f | %s | ถืออยู่   ", tag, kname, (is_sell ? "S" : "B"), g_rt[i].lot, BarMinText(t_in))
                        : StringFormat("%s %s %s %.2f | %s | %s %+.0f ($%+.2f)   ", tag, kname, (is_sell ? "S" : "B"), g_rt[i].lot,
                                       BarMinText(t_in), ReplayReasonName(r), g_rt[i].pnl, g_rt[i].usd));

   string tipText = StringFormat("จำลอง ชุด #%d %s %s: %s %.2f lot | Stop @ %s → ได้ %s (%s, %s ของแท่ง) | SL %s (%s)",
                                 g_rt[i].set_id, tag, kname, otype, g_rt[i].lot, DoubleToString(g_rt[i].p_order, _Digits),
                                 DoubleToString(g_rt[i].p_in, _Digits), TimeToString(t_in, TIME_DATE|TIME_SECONDS), BarMinText(t_in),
                                 DoubleToString(g_rt[i].sl0, _Digits), slwhy);
   tipText += StringFormat("\nสัญญาณ %s | Z ตอนสัญญาณ R %+.2f / S %+.2f | สุดขั้วระหว่างเฝ้า R %+.2f / S %+.2f | ลึกสุด T%d | ไม้ที่ %d ของแท่ง",
                           TimeToString(t_sig, TIME_DATE|TIME_SECONDS), g_rt[i].zr, g_rt[i].zs, g_rt[i].ext_r, g_rt[i].ext_s, g_rt[i].max_tier, g_rt[i].bar_seq);
   if(open)
      tipText += StringFormat("\nตัดจบ %s (ปิดแท่งที่ %d หลังแท่งที่ถูกเกี่ยว)", TimeToString((datetime)(g_rt[i].exit_msc / 1000), TIME_DATE|TIME_MINUTES), InpExitBars);
   else
      tipText += StringFormat("\nออก %s @ %s (%s) | %+.0f จุด | $%+.2f | ถือ %d วินาที",
                              ReplayReasonName(r), DoubleToString(g_rt[i].p_out, _Digits),
                              TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS),
                              g_rt[i].pnl, g_rt[i].usd, (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000))
               + StringFormat("\nระยะกำไรระหว่างถือ: ต่ำสุด %+.0f / สูงสุด %+.0f / เฉลี่ย %+.0f จุด",
                              PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ProfitAvgPts(i));
   tipText += "\n" + SignalFactorText(i);
   if(g_rt[i].ss_ok)
      tipText += StringFormat("\nเร็ว (Z ตัวใดก็ได้ จาก %.1f) → %s | ค้าง Z ≥ %.1f ต่อเนื่อง %s (รวมในแท่ง %s) | K2 %d",
                              InpSpeedFromZ, SpeedLong(g_rt[i].ss.sp[2]), InpZoneZ, ShortSec(g_rt[i].zone_run),
                              ShortSec(g_rt[i].ss.zone_cum_ms / 1000), g_rt[i].ss.k2);
   tipText += StringFormat("\nแท่งก่อนหน้าติดกัน: ยอด Z ≥ %.1f %d แท่ง / ปิด ≥ %.1f %d แท่ง", InpZoneZ, g_rt[i].prev_pk, InpZoneZ, g_rt[i].prev_cl);
   if(g_htf_ok)
      tipText += StringFormat(" | %s ณ ตอนสัญญาณ: %s (Z_reg %+.2f / Z_SMA %+.2f)", HTFName(),
                              (g_rt[i].htf_tier > 0 ? StageTag(g_rt[i].htf_tier) : "ไม่ถึง"), g_rt[i].htf_zr, g_rt[i].htf_zs);
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tipText);
   if(!open) ObjectSetString(0, nl, OBJPROP_TOOLTIP, tipText);

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

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rt); i++)
      if(!g_rt[i].drawn_final) DrawReplayTrade(i);
   if(InpShowReplayBlocked)
      for(; g_rb_drawn < ArraySize(g_rb); g_rb_drawn++) DrawReplayBlocked(g_rb_drawn);
}

// ผลของชุดที่ขาแรกอยู่ที่ index i (ขาสวน i, ขาตาม i + 1): 0 = ยังไม่จบ / 1 = ไม่ถูกเกี่ยว / 2 = เกี่ยวขาสวน / 3 = เกี่ยวขาตาม / 4 = เกี่ยวทั้งคู่
int SetResult(int i) {
   if(i + 1 >= ArraySize(g_rt) || g_rt[i + 1].set_id != g_rt[i].set_id) return 0;
   for(int m = 0; m < 2; m++) if(g_rt[i + m].reason == RX_PEND || g_rt[i + m].reason == RX_OPEN) return 0;
   bool c = (g_rt[i].msc_in > 0), f = (g_rt[i + 1].msc_in > 0);
   return (c && f) ? 4 : (c ? 2 : (f ? 3 : 1));
}

string SetResultCode(int r) {
   switch(r) {
      case 1: return "NONE";
      case 2: return "COUNTER";
      case 3: return "TREND";
      case 4: return "BOTH";
   }
   return "OPEN";
}

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n = 0, w = 0, c_tm = 0, c_sl = 0, c_wk = 0;
   int    kn[2], kw[2];
   double ku[2];
   int    cnt[5];
   double usd_st[5];
   ArrayInitialize(kn, 0); ArrayInitialize(kw, 0); ArrayInitialize(ku, 0.0);
   ArrayInitialize(cnt, 0);
   ArrayInitialize(usd_st, 0.0);
   double usd = 0.0, peak = 0.0, dd = 0.0;
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(!RDone(g_rt[i].reason)) continue;
      n++;
      if(g_rt[i].usd > 0.0) w++;
      usd += g_rt[i].usd;
      if(usd > peak) peak = usd;
      if(usd - peak < dd) dd = usd - peak;
      int st = MathMax(1, MathMin(4, g_rt[i].stage));
      cnt[st]++;
      usd_st[st] += g_rt[i].usd;
      int k = g_rt[i].kind;
      kn[k]++; ku[k] += g_rt[i].usd; if(g_rt[i].usd > 0.0) kw[k]++;
      switch(g_rt[i].reason) {
         case RX_TIME: c_tm++; break;
         case RX_SL:   c_sl++; break;
         case RX_WEEK: c_wk++; break;
      }
   }
   int sr[5];
   ArrayInitialize(sr, 0);
   for(int i = 0; i < ArraySize(g_rt); i++) if(g_rt[i].kind == 0) sr[SetResult(i)]++;
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | ตัดจบ %d SL %d ปิดสัปดาห์ %d | ถูกทิ้ง %d",
                           InpReplayDays, g_rp_status, n, (n > 0 ? 100.0 * w / n : 0.0), usd, dd,
                           c_tm, c_sl, c_wk, ArraySize(g_rb));
   s += StringFormat("\n   สวน %d ไม้ ชนะ %.0f%% $%+.2f | ตาม %d ไม้ ชนะ %.0f%% $%+.2f",
                     kn[0], (kn[0] > 0 ? 100.0 * kw[0] / kn[0] : 0.0), ku[0], kn[1], (kn[1] > 0 ? 100.0 * kw[1] / kn[1] : 0.0), ku[1]);
   s += StringFormat("\n   ชุด %d ชุด: ไม่ถูกเกี่ยว %d | เกี่ยวขาสวน %d | เกี่ยวขาตาม %d | เกี่ยวทั้งคู่ %d%s",
                     g_set_n, sr[1], sr[2], sr[3], sr[4], (g_set_on ? " | มีชุดที่ยังไม่จบ" : ""));
   string tail = "";
   if(g_rp_skip_n > 0) tail += StringFormat(" | ⚠️ ข้ามช่วงที่ดึง tick ไม่ได้ %d ช่วง (ล่าสุด %s)", g_rp_skip_n, g_rp_skip_txt);
   s += StringFormat("\n   T2 %d ไม้ ($%+.2f) | T3 %d ไม้ ($%+.2f) | T4 %d ไม้ ($%+.2f)%s",
                     cnt[2], usd_st[2], cnt[3], usd_st[3], cnt[4], usd_st[4], tail);
   if(n > 0) {   // ระยะกำไรระหว่างถือ เฉลี่ยต่อไม้
      double s_min = 0.0, s_max = 0.0, s_avg = 0.0;
      for(int i = 0; i < ArraySize(g_rt); i++) {
         if(!RDone(g_rt[i].reason)) continue;
         s_min += PriceToPts(g_rt[i].mae);
         s_max += PriceToPts(g_rt[i].mfe);
         s_avg += ProfitAvgPts(i);
      }
      s += StringFormat("\n   ระยะกำไรระหว่างถือ (เฉลี่ยต่อไม้): ต่ำสุด %+.0f / สูงสุด %+.0f / เฉลี่ย %+.0f จุด", s_min / n, s_max / n, s_avg / n);
   }
   int bn[4];
   ArrayInitialize(bn, 0);
   for(int k = 0; k < ArraySize(g_bo); k++) bn[g_bo[k].result]++;
   int bd = bn[BO_REV] + bn[BO_CONT] + bn[BO_UNC];
   if(bd > 0)
      s += StringFormat("\n   แท่ง Z ≥ %.1f: %d แท่ง | ภายใน %d นาทีหลังยอด: สวนกลับ %.0f%% / พุ่งต่อ %.0f%% / ไม่ชัด %.0f%% (รอผล %d)",
                        InpZoneZ, bd, InpOutcomeMin, 100.0 * bn[BO_REV] / bd, 100.0 * bn[BO_CONT] / bd, 100.0 * bn[BO_UNC] / bd, bn[BO_WAIT]);
   if(InpReplayCSV && g_rp_csv_rows >= 0)
      s += StringFormat("\n   📄 CSV: MQL5\\Files\\%s (%d ไม้)", ReplayCSVName(), g_rp_csv_rows);
   if(InpReplayCSV && g_set_csv_rows >= 0)
      s += StringFormat(" | %s (%d ชุด)", ReplaySetsCSVName(), g_set_csv_rows);
   if(InpBarCSV && g_bo_csv_rows >= 0)
      s += StringFormat(" | %s (%d แท่ง)", ReplayBarsCSVName(), g_bo_csv_rows);
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
   return s;
}

const int RP_SKIP_SEC = 30;   // ดึง tick ช่วงหนึ่งไม่สำเร็จนานเกินนี้ → ข้ามช่วงนั้น

string ReplayCSVName() { return "7LCEA_Replay_" + _Symbol + ".csv"; }

string ReplayReasonCode(int r) {
   switch(r) {
      case RX_TIME: return "TIME";
      case RX_SL:   return "SL";
      case RX_WEEK: return "WEEKCLOSE";
      case RX_PEND: return "PENDING";
      case RX_EXP:  return "EXPIRED";
   }
   return "OPEN";
}

string CsvNum(bool ok, double v, int digits) { return ok ? DoubleToString(v, digits) : ""; }

// ความเร็วรวม (Z ตัวใดก็ได้): วินาทีถึง T2,T3,T4 + star + อัตราพุ่งถึง T2 (Z/วินาที)
string CsvSpeedAny(bool ok, const ZSpeed &sp) {
   double rate = ok ? SpeedRate(sp, 0) : -1.0;
   return CsvSpeed(ok, sp) + (rate >= 0.0 ? DoubleToString(rate, 4) : "") + ",";
}

// ความเร็ว Z ตอนยิง: วินาทีถึง T2,T3,T4 (ว่าง = ยังไม่ถึง / ไม่มีข้อมูล) + star (1 = นับจากเวลาเปิดแท่ง)
string CsvSpeed(bool ok, const ZSpeed &sp) {
   string s = "";
   bool   st = false;
   for(int k = 0; k < 3; k++) {
      bool has = ok && sp.sec[k] >= 0;
      s += (has ? IntegerToString(sp.sec[k]) : "") + ",";
      if(has && sp.star_k[k]) st = true;
   }
   return s + (ok ? (st ? "1" : "0") : "") + ",";
}

// เขียนไม้จำลองที่ปิดแล้ว + ปัจจัยตอนยิง + ระยะกำไรระหว่างถือ (เขียนใหม่ทั้งไฟล์เมื่อมีไม้ปิดเพิ่ม)
void ReplayWriteCSV(int done) {
   string fn = ReplayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "set_id,order_kind,signal_time,signal_side,order_price,sl_mode," +
                      "time_in,side,tier,max_tier,bar_seq,lot,price_in,sl_peak,sl_init_pts,z_reg,z_sma,ext_zreg,ext_zsma,z_float,z_open,z_gap," +
                      "a_break_pts,a_avg_range_pts,a_break_ratio,b_move_last30_pts,b_move_prev30_pts," +
                      "c_zreg_drop,c_zsma_drop,d_pull_pts,d_pull_frac,e_ticks_per_sec_last15,e_ticks_per_sec_prev60," +
                      "spd_zreg_t2_sec,spd_zreg_t3_sec,spd_zreg_t4_sec,spd_zreg_from_open,spd_zsma_t2_sec,spd_zsma_t3_sec,spd_zsma_t4_sec,spd_zsma_from_open," +
                      "spd_any_t2_sec,spd_any_t3_sec,spd_any_t4_sec,spd_any_from_open,spd_any_rate_t2," +
                      "zone_run_sec,zone_cum_sec,zone_max_sec,prev_bars_peak_zone,prev_bars_close_zone,k2,k2_max," +
                      "zreg_bar_open,zreg_bar_high,zreg_bar_low,zsma_bar_open,zsma_bar_high,zsma_bar_low,htf_tier,htf_zreg,htf_zsma," +
                      "time_out,exit,hold_sec,pnl_pts,usd,profit_min_pts,profit_max_pts,profit_avg_pts\r\n");
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(!RDone(g_rt[i].reason)) continue;
      string ln = StringFormat("%d,%s,%s,%s,%s,%s,", g_rt[i].set_id, (g_rt[i].kind == 0 ? "COUNTER" : "TREND"),
                               TimeToString((datetime)(g_rt[i].msc_sig / 1000), TIME_DATE|TIME_SECONDS), (g_rt[i].sig_dir == -1 ? "UP" : "DOWN"),
                               DoubleToString(g_rt[i].p_order, _Digits), SLModeCode(g_rt[i].sl_mode));
      ln += StringFormat("%s,%s,%d,%d,%d,%.2f,%s,%s,%.0f,%.3f,%.3f,%.3f,%.3f,",
                               TimeToString((datetime)(g_rt[i].msc_in / 1000), TIME_DATE|TIME_SECONDS), (g_rt[i].dir == -1 ? "SELL" : "BUY"),
                               g_rt[i].stage, g_rt[i].max_tier, g_rt[i].bar_seq, g_rt[i].lot, DoubleToString(g_rt[i].p_in, _Digits),
                               DoubleToString(g_rt[i].peak, _Digits),
                               PriceToPts(MathAbs(g_rt[i].sl0 - g_rt[i].p_in)), g_rt[i].zr, g_rt[i].zs, g_rt[i].ext_r, g_rt[i].ext_s);
      ln += StringFormat("%.3f,%.3f,%.3f,", g_rt[i].z_float, g_rt[i].z_open, g_rt[i].z_gap);
      bool af = g_rt[i].a_ok && g_rt[i].a_rng > 0.0;
      ln += CsvNum(g_rt[i].a_ok, g_rt[i].a_brk, 0) + "," + CsvNum(g_rt[i].a_ok, g_rt[i].a_rng, 0) + "," +
            CsvNum(af, (af ? g_rt[i].a_brk / g_rt[i].a_rng : 0.0), 3) + ",";
      ln += CsvNum(g_rt[i].b_ok, g_rt[i].b_m1, 0) + "," + CsvNum(g_rt[i].b_ok, g_rt[i].b_m0, 0) + ",";
      bool pf = g_rt[i].a_ok && g_rt[i].a_brk > 0.0;
      ln += StringFormat("%.3f,%.3f,%.0f,", g_rt[i].c_dzr, g_rt[i].c_dzs, g_rt[i].d_pull) +
            CsvNum(pf, (pf ? g_rt[i].d_pull / g_rt[i].a_brk : 0.0), 3) + ",";
      ln += CsvNum(g_rt[i].e_ok, g_rt[i].e_r15, 2) + "," + CsvNum(g_rt[i].e_ok, g_rt[i].e_r60, 2) + ",";
      bool so = g_rt[i].ss_ok;
      ln += CsvSpeed(so, g_rt[i].ss.sp[0]) + CsvSpeed(so, g_rt[i].ss.sp[1]) + CsvSpeedAny(so, g_rt[i].ss.sp[2]);
      ln += StringFormat("%I64d,", g_rt[i].zone_run) +
            CsvNum(so, (double)(g_rt[i].ss.zone_cum_ms / 1000), 0) + "," + CsvNum(so, (double)(g_rt[i].ss.zone_max_ms / 1000), 0) + "," +
            StringFormat("%d,%d,", g_rt[i].prev_pk, g_rt[i].prev_cl) +
            CsvNum(so, g_rt[i].ss.k2, 0) + "," + CsvNum(so, g_rt[i].ss.k2_max, 0) + ",";
      ln += StringFormat("%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,", g_rt[i].zb[0], g_rt[i].zb[1], g_rt[i].zb[2], g_rt[i].zb[3], g_rt[i].zb[4], g_rt[i].zb[5]);
      ln += StringFormat("%d,%.3f,%.3f,", g_rt[i].htf_tier, g_rt[i].htf_zr, g_rt[i].htf_zs);
      ln += StringFormat("%s,%s,%d,%.0f,%.2f,%.0f,%.0f,%.0f\r\n",
                         TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS), ReplayReasonCode(g_rt[i].reason),
                         (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000), g_rt[i].pnl, g_rt[i].usd,
                         PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ProfitAvgPts(i));
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_rp_csv_rows < 0) PrintFormat("📄 บันทึกไม้จำลอง %d ไม้ + ปัจจัยตอนยิง ลง MQL5\\Files\\%s (อัปเดตเมื่อมีไม้ปิดเพิ่ม)", done, fn);
   g_rp_csv_rows = done;
}

string ReplaySetsCSVName() { return "7LCEA_Sets_" + _Symbol + ".csv"; }

// ขาของชุด 1 ฝั่ง → "FILLED,เวลาเกี่ยว,ราคาเข้า,ทางออก,จุด,usd,"
string CsvLeg(int i) {
   bool f = (g_rt[i].msc_in > 0);
   return StringFormat("%s,%s,%s,%s,%s,%s,", (f ? "1" : "0"),
                       (f ? TimeToString((datetime)(g_rt[i].msc_in / 1000), TIME_DATE|TIME_SECONDS) : ""),
                       (f ? DoubleToString(g_rt[i].p_in, _Digits) : ""), ReplayReasonCode(g_rt[i].reason),
                       (f ? DoubleToString(g_rt[i].pnl, 0) : ""), (f ? DoubleToString(g_rt[i].usd, 2) : ""));
}

// 1 แถวต่อ 1 ชุด (สัญญาณ) ที่จบแล้ว: ไม่ถูกเกี่ยว / เกี่ยวขาเดียว / ทั้งคู่ + ผลแต่ละขา + ค่าตอนสัญญาณ
void ReplayWriteSetsCSV(int done) {
   string fn = ReplaySetsCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "set_id,signal_time,signal_side,tier,max_tier,lot,z_reg,z_sma,ext_zreg,ext_zsma,z_float,bar_extreme," +
                      "spd_any_t2_sec,zone_run_sec,k2,prev_bars_peak_zone,htf_tier," +
                      "counter_price,counter_sl,counter_sl_mode,trend_price,trend_sl,trend_sl_mode,filled," +
                      "counter_filled,counter_time_in,counter_price_in,counter_exit,counter_pnl_pts,counter_usd," +
                      "trend_filled,trend_time_in,trend_price_in,trend_exit,trend_pnl_pts,trend_usd,set_usd\r\n");
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].kind != 0) continue;
      int r = SetResult(i);
      if(r == 0) continue;
      int c = i, f = i + 1;
      string ln = StringFormat("%d,%s,%s,%d,%d,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%s,",
                               g_rt[c].set_id, TimeToString((datetime)(g_rt[c].msc_sig / 1000), TIME_DATE|TIME_SECONDS),
                               (g_rt[c].sig_dir == -1 ? "UP" : "DOWN"), g_rt[c].stage, g_rt[c].max_tier, g_rt[c].lot,
                               g_rt[c].zr, g_rt[c].zs, g_rt[c].ext_r, g_rt[c].ext_s, g_rt[c].z_float, DoubleToString(g_rt[c].peak, _Digits));
      bool so = g_rt[c].ss_ok;
      ln += CsvNum(so && g_rt[c].ss.sp[2].sec[0] >= 0, g_rt[c].ss.sp[2].sec[0], 0) + "," +
            StringFormat("%I64d,", g_rt[c].zone_run) + CsvNum(so, g_rt[c].ss.k2, 0) + "," +
            StringFormat("%d,%d,", g_rt[c].prev_pk, g_rt[c].htf_tier);
      ln += StringFormat("%s,%s,%s,%s,%s,%s,%s,", DoubleToString(g_rt[c].p_order, _Digits), DoubleToString(g_rt[c].sl0, _Digits),
                         SLModeCode(g_rt[c].sl_mode), DoubleToString(g_rt[f].p_order, _Digits), DoubleToString(g_rt[f].sl0, _Digits),
                         SLModeCode(g_rt[f].sl_mode), SetResultCode(r));
      ln += CsvLeg(c) + CsvLeg(f) + DoubleToString(g_rt[c].usd + g_rt[f].usd, 2) + "\r\n";
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_set_csv_rows < 0) PrintFormat("📄 บันทึกชุดออเดอร์ %d ชุด ลง MQL5\\Files\\%s (อัปเดตเมื่อมีชุดจบเพิ่ม)", done, fn);
   g_set_csv_rows = done;
}

string ReplayBarsCSVName() { return "7LCEA_Bars_" + _Symbol + ".csv"; }

// เขียนแท่งที่ Z ≥ InpZoneZ ที่รู้ผลแล้ว (เขียนใหม่ทั้งไฟล์เมื่อมีแท่งรู้ผลเพิ่ม)
void ReplayWriteBarsCSV(int done) {
   string fn = ReplayBarsCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "bar_time,side,peak_z,zreg_open,zreg_high,zreg_low,zreg_close,zsma_open,zsma_high,zsma_low,zsma_close,z_float_dir," +
                      "tick_from_bar_open,spd_zreg_t2_sec,spd_zreg_t3_sec,spd_zreg_t4_sec,spd_zreg_from_open,spd_zsma_t2_sec,spd_zsma_t3_sec,spd_zsma_t4_sec,spd_zsma_from_open," +
                      "spd_any_t2_sec,spd_any_t3_sec,spd_any_t4_sec,spd_any_from_open,spd_any_rate_t2," +
                      "zone_cum_sec,zone_max_sec,bars_peak_zone,bars_close_zone,k2,k2_max,htf_tier,htf_zreg,htf_zsma," +
                      "ext_time,ext_price,sigma_pts,result,result_min,max_rev_sigma,max_cont_pts,trades,trades_usd\r\n");
   for(int k = 0; k < ArraySize(g_bo); k++) {
      if(g_bo[k].result == BO_WAIT) continue;
      int    dir = (g_bo[k].side == 0) ? -1 : 1;
      string ln  = StringFormat("%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,",
                                TimeToString(g_bo[k].bar, TIME_DATE|TIME_MINUTES), (g_bo[k].side == 0 ? "UP" : "DOWN"), g_bo[k].st.peak_z,
                                g_bo[k].zr[0], g_bo[k].zr[1], g_bo[k].zr[2], g_bo[k].zr[3],
                                g_bo[k].zs[0], g_bo[k].zs[1], g_bo[k].zs[2], g_bo[k].zs[3], ZFloat(dir, g_bo[k].fz), (g_bo[k].fresh ? 1 : 0));
      ln += CsvSpeed(true, g_bo[k].st.sp[0]) + CsvSpeed(true, g_bo[k].st.sp[1]) + CsvSpeedAny(true, g_bo[k].st.sp[2]);
      ln += StringFormat("%I64d,%I64d,%d,%d,%d,%d,", g_bo[k].st.zone_cum_ms / 1000, g_bo[k].st.zone_max_ms / 1000,
                         g_bo[k].peak_n, g_bo[k].close_n, g_bo[k].st.k2, g_bo[k].st.k2_max);
      ln += StringFormat("%d,%.3f,%.3f,", g_bo[k].htf_tier, g_bo[k].htf_zr, g_bo[k].htf_zs);
      int    nt  = 0;
      double usd = 0.0;
      for(int i = 0; i < ArraySize(g_rt); i++)   // ไม้จำลองของสัญญาณในแท่งนี้ ฝั่งนี้ (ถูกเกี่ยวแล้วปิดแล้ว ทั้งขาสวน / ตาม)
         if(RDone(g_rt[i].reason) && g_rt[i].sig_dir == dir && BarStartOf((datetime)(g_rt[i].msc_sig / 1000)) == g_bo[k].bar) { nt++; usd += g_rt[i].usd; }
      ln += StringFormat("%s,%s,%.0f,%s,%.1f,%.2f,%.0f,%d,%.2f\r\n",
                         TimeToString((datetime)(g_bo[k].st.ext_msc / 1000), TIME_DATE|TIME_SECONDS), DoubleToString(g_bo[k].st.ext_px, _Digits),
                         PriceToPts(g_bo[k].st.ext_sd), BarResultCode(g_bo[k].result),
                         (double)(g_bo[k].res_msc - g_bo[k].st.ext_msc) / 60000.0, g_bo[k].max_rev, g_bo[k].max_cont, nt, usd);
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_bo_csv_rows < 0) PrintFormat("📄 บันทึกแท่งที่ Z ≥ %.1f จำนวน %d แท่ง + ผลหลังยอด ลง MQL5\\Files\\%s (อัปเดตเมื่อรู้ผลเพิ่ม)", InpZoneZ, done, fn);
   g_bo_csv_rows = done;
}

// เรียกทุก 1 วินาที: ไล่เล่นซ้ำทีละช่วง (ครั้งแรกทีละ 12 ชม.) จนถึงปัจจุบัน แล้วต่อแบบสด
void ReplayStep() {
   if(!g_draw || !InpShowReplay) return;
   if(!g_rp_init) {
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
      if(got < 0) {   // ดึงไม่สำเร็จ → รอ (MT5 กำลังโหลดจากโบรก) ไม่เกิน RP_SKIP_SEC แล้วข้ามช่วงนี้ไป
         int err = GetLastError();
         if(g_rp_fail_cur != g_rp_cursor) { g_rp_fail_cur = g_rp_cursor; g_rp_fail_ms = GetTickCount(); }
         uint waited = (GetTickCount() - g_rp_fail_ms) / 1000;
         string rng = TimeToString((datetime)(g_rp_cursor / 1000), TIME_DATE|TIME_MINUTES) + " – " + TimeToString((datetime)(to / 1000), TIME_DATE|TIME_MINUTES);
         if(g_rp_caught || waited < (uint)RP_SKIP_SEC) {
            g_rp_status = StringFormat("⏳ กำลังโหลด tick ช่วง %s (error %d, รอมา %d วิ%s)", rng, err, (int)waited,
                                       (g_rp_caught ? "" : StringFormat(", ครบ %d วิ = ข้ามช่วงนี้", RP_SKIP_SEC)));
            return;
         }
         g_rp_skip_n++;
         g_rp_skip_txt = rng + StringFormat(" (error %d)", err);
         PrintFormat("⚠️ Tick Replay: ดึง tick ช่วง %s ไม่สำเร็จเกิน %d วิ (error %d) → ข้ามช่วงนี้", rng, RP_SKIP_SEC, err);
         g_rp_cursor   = to + 1;
         g_rp_fail_cur = -1;
         return;
      }
      g_rp_fail_cur = -1;
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
   if(!g_rp_caught && to >= now_msc - 2000) {
      g_rp_caught = true;
      g_barz_bar  = 0;   // เล่นซ้ำครบ → วาดป้าย Z บนแท่งใหม่ทั้งชุด (มีความเร็ว Z ของแท่งย้อนหลังแล้ว)
   }
   if(g_rp_caught) ReplayTimeEvents(now_msc);   // เวลาผ่านไปโดยไม่มี tick (ปิดสัปดาห์ / ยิงหลังครบเวลาเฝ้า)

   g_rp_status = g_rp_caught
                 ? StringFormat("✅ ครบแล้ว + เดินต่อแบบสด (%I64d ticks)", g_rp_ticks)
                 : StringFormat("⏳ กำลังเล่นซ้ำ ถึง %s (%I64d ticks)", TimeToString((datetime)(g_rp_cursor / 1000), TIME_DATE|TIME_MINUTES), g_rp_ticks);
   ReplayDraw();
   if(InpReplayCSV && g_rp_caught) {
      int done = 0;
      for(int i = 0; i < ArraySize(g_rt); i++) if(RDone(g_rt[i].reason)) done++;
      if(done != g_rp_csv_rows) ReplayWriteCSV(done);
      int sets = 0;
      for(int i = 0; i < ArraySize(g_rt); i++) if(g_rt[i].kind == 0 && SetResult(i) > 0) sets++;
      if(sets != g_set_csv_rows) ReplayWriteSetsCSV(sets);
   }
   if(InpBarCSV && g_rp_caught) {
      int done = 0;
      for(int k = 0; k < ArraySize(g_bo); k++) if(g_bo[k].result != BO_WAIT) done++;
      if(done != g_bo_csv_rows) ReplayWriteBarsCSV(done);
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
                   StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s) | T2 ทั้งคู่ > %.2f (ลอย ≤ %.1f) / T3 ตัวใด > %.2f / T4 ตัวใด > %.2f",
                                g_z_reg, DoubleToString(g_center, _Digits), g_z_sma, DoubleToString(g_sma_mean, _Digits),
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
   return StringFormat("เฝ้า %s ยิงใน %.1f วิ", StageTag(w.tier), left);
}

string WatchText(const WatchState &w, bool is_sell, long now_msc) {
   string   sg   = is_sell ? "+" : "−";
   int      dir  = is_sell ? -1 : 1;
   double   zf   = ZFloat(dir, g_bar0_fz);
   string   hold = SetActive() ? " | ⏸️ ชุดออเดอร์ยังไม่จบ (ยังไม่หาสัญญาณใหม่)" : "";
   if(w.active) {
      double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
      if(left < 0.0) left = 0.0;
      string need = (w.tier >= 4) ? StringFormat("Z ตัวใด > %s%.2f, ยิงทันที", sg, InpT4_Z)
                  : (w.tier == 3) ? StringFormat("Z ตัวใด > %s%.2f, รอ %d วิ", sg, InpT3_Z, InpT3_Sec)
                  : StringFormat("Z %s > %s%.2f, รอ %d วิ", (zf > InpT2EitherFloat ? "ตัวใด (ลอย > " + DoubleToString(InpT2EitherFloat, 1) + ")" : "ทั้งคู่"),
                                 sg, InpT2_Z, InpT2_Sec);
      double dist = PtsToPrice(InpStopDist_Pts);
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      return StringFormat("👀 เฝ้า %s (%s, Lot %.2f) | สุดขั้ว R %+.2f / S %+.2f | ถ้าวางตอนนี้: สวน %s @ %s (SL %s) / ตาม %s @ %s (SL เปิดแท่ง %s) | ไม่มีค่าใหม่มา %.1f วิ → วางในอีก %.1f วิ%s",
                          StageTag(w.tier), need, TierLot(w.tier), w.ext_r, w.ext_s,
                          (dir == -1 ? "SELL STOP" : "BUY STOP"), DoubleToString(dir == -1 ? bid - dist : ask + dist, _Digits),
                          DoubleToString(SLPrice(dir, g_bar0_hi, g_bar0_lo), _Digits),
                          (dir == -1 ? "BUY STOP" : "SELL STOP"), DoubleToString(dir == -1 ? ask + dist : bid - dist, _Digits),
                          DoubleToString(g_bar0_open, _Digits), (double)(now_msc - w.last_new) / 1000.0, left, hold);
   }
   string t2  = !g_en[2] ? "T2 ปิดปุ่ม"
              : (InpFloatFilter && zf <= InpFloatMin) ? StringFormat("T2 ปิด (ลอย %+.2f ≤ %.2f)", zf, InpFloatMin)
              : StringFormat("T2 Z %s > %s%.2f", (zf > InpT2EitherFloat ? "ตัวใด" : "ทั้งคู่"), sg, InpT2_Z);
   string t34 = (!g_en[3] && !g_en[4]) ? "T3/T4 ปิดปุ่ม"
              : StringFormat("%s / %s", (g_en[3] ? StringFormat("T3 Z ตัวใด > %s%.2f", sg, InpT3_Z) : "T3 ปิดปุ่ม"),
                                        (g_en[4] ? StringFormat("T4 > %s%.2f", sg, InpT4_Z) : "T4 ปิดปุ่ม"));
   return StringFormat("✅ รอ %s | %s (Z_float %+.2f)%s", t2, t34, zf, hold);
}

string PositionLines(double bid, double ask, datetime now) {
   string out = "";
   for(int i = OrdersTotal() - 1; i >= 0; i--) {   // ออเดอร์รอของชุด
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder()) continue;
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      long     left  = (long)(BarStartOf(setup) + (datetime)PeriodSeconds(InpZ_Timeframe) - now);
      bool     buy   = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP);
      out += StringFormat("\n  ⏳ #%I64u %s %s %.2f @ %s | SL %s | ยกเลิกถ้ายังไม่ถูกเกี่ยวในอีก %s",
                          ticket, KindFromComment(OrderGetString(ORDER_COMMENT)), (buy ? "BUY STOP" : "SELL STOP"),
                          OrderGetDouble(ORDER_VOLUME_CURRENT), DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), _Digits),
                          DoubleToString(OrderGetDouble(ORDER_SL), _Digits), FormatDuration(MathMax(0, left)));
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      bool     is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl     = PositionGetDouble(POSITION_SL);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double   prof   = is_buy ? PriceToPts(bid - open) : PriceToPts(open - ask);
      out += StringFormat("\n  #%I64u %s %s %.2f @ %s | กำไร %+.0f จุด | SL %s | ถือ %s | ตัดจบในอีก %s",
                          ticket, KindFromComment(PositionGetString(POSITION_COMMENT)), (is_buy ? "BUY" : "SELL"), PositionGetDouble(POSITION_VOLUME),
                          DoubleToString(open, _Digits), prof, DoubleToString(sl, _Digits), FormatDuration((long)(now - opened)),
                          FormatDuration(MathMax(0, (long)(ExitTimeOf(opened) - now))));
   }
   return out;
}

// สถิติ tick ของแท่งปัจจุบันแบบอ่านง่าย (Dashboard / log ตอนเปิดไม้)
string LiveStatText(int side, long now_msc) {
   BarSpeed bs;
   if(!SpeedOf(CurrentZBarTime(), bs)) return "ยังไม่มีข้อมูล tick";
   SideStat st;
   st = bs.sd[side];
   long run = ZoneRunSec(g_trk_live.tr[side], now_msc);
   double rate = SpeedRate(st.sp[2], 0);
   return StringFormat("เร็ว (จาก Z %.1f) %s%s · ค้าง Z ≥ %.1f ตอนนี้ %s / นานสุด %s / รวม %s · K2 %d · Z สูงสุด %+.2f",
                       InpSpeedFromZ, SpeedLong(st.sp[2]), (rate >= 0.0 ? StringFormat(" (%.2f Z/วิ)", rate) : ""),
                       InpZoneZ, ShortSec(run), ShortSec(st.zone_max_ms / 1000), ShortSec(st.zone_cum_ms / 1000), st.k2,
                       (st.peak_z > -90.0 ? st.peak_z : 0.0));
}

void UpdateDashboard(int ts, datetime now) {
   if(!g_draw || !InpShowDashboard) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int buys, sells;
   CountPositions(buys, sells);

   string z_str = g_z_valid
      ? StringFormat("Z_reg %+.2f (กลาง %s, σ %.0f จุด%s)  |  Z_SMA %+.2f (SMA20 %s, σ %.0f จุด) | ต่าง %+.2f",
                     g_z_reg, DoubleToString(g_center, _Digits), PriceToPts(g_sigma), (g_sigma_floor ? " พื้น" : ""),
                     g_z_sma, DoubleToString(g_sma_mean, _Digits), PriceToPts(g_sma_sd), g_z_reg - g_z_sma)
      : "รอข้อมูลแท่งเทียน...";
   string news_str = NextNewsText(now);

   long   now_msc = MathMax(g_last_tick_msc, (long)now * 1000);
   string msg = StringFormat("=== 📊 7-Lines Counter EA v14.31 (%s T2 ลอย>%.2f Z ทั้งคู่>%.1f %d วิ (ลอย>%.1f ตัวเดียวได้) | %s T3 Z ตัวใด>%.1f %d วิ | %s T4 >%.1f ทันที | Stop ±%.0f: สวน SL ยอด±%.0f / ตาม SL เปิดแท่ง | ตัดจบ %d แท่ง) ===\n",
                             (g_en[2] ? "✅" : "⛔"), InpFloatMin, InpT2_Z, InpT2_Sec, InpT2EitherFloat, (g_en[3] ? "✅" : "⛔"), InpT3_Z, InpT3_Sec,
                             (g_en[4] ? "✅" : "⛔"), InpT4_Z, InpStopDist_Pts, InpSLPeak_Pts, InpExitBars);
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : R %+.2f / S %+.2f%s\n", g_prev_close_zr, g_prev_close_zs, (news_str == "" ? "" : " | " + news_str));
   if(g_z_valid)   // ÷ SD20, + = เหนือ SMA (ฝั่ง SELL ใช้ค่านี้ / ฝั่ง BUY ใช้ค่าลบ)
      msg += StringFormat("ระยะจาก SMA : Z_float %+.2f (ราคาเปิด %s vs SMA ตอนเปิดแท่ง %s) | Z_gap (ถดถอย − SMA) %+.2f\n",
                          g_bar0_fz, DoubleToString(g_bar0_open, _Digits), DoubleToString(g_bar0_fsma, _Digits),
                          ZFromSMA(-1, g_center, g_sma_mean, g_sma_sd));
   msg += "SELL : " + WatchText(g_wsell, true,  now_msc) + "\n";
   msg += "BUY  : " + WatchText(g_wbuy,  false, now_msc) + "\n";
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts);
   if(InpShowZSpeed) {
      msg += "แท่งนี้ SELL : " + LiveStatText(0, now_msc) + "\n";
      msg += "แท่งนี้ BUY  : " + LiveStatText(1, now_msc) + "\n";
   }
   if(InpShowHTF && g_htf_ok) {
      double zr0, zs0, zr1, zs1;
      datetime hb;
      int t0 = HTFTierAt(now, 0, zr0, zs0, hb), t1 = HTFTierAt(now, 1, zr1, zs1, hb);
      msg += StringFormat("%s แท่งนี้ : SELL %s (R %+.2f / S %+.2f) | BUY %s (R %+.2f / S %+.2f)\n", HTFName(),
                          (t0 > 0 ? StageTag(t0) : "−"), zr0, zs0, (t1 > 0 ? StageTag(t1) : "−"), zr1, zs1);
   }
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
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
const string PANEL_PREFIX = "7LCEA_PN_";
const int    LAYOUT_MAX_SHIFT = 3;   // ป้ายบนแท่งเลื่อนออกจากแท่งได้ไม่เกินกี่แถว (เกิน = ซ่อน)

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

void DrawTierButtons() {
   if(!g_draw) return;
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
   g_htf_bar     = 0;   // กรอบ TF ใหญ่ใช้ปุ่ม T2-T4 ด้วย → วาดใหม่ทั้งชุด
   g_barz_bar    = 0;
   g_last_status = StringFormat("%s %s (ปุ่ม) — Tick Replay เริ่มเล่นซ้ำใหม่", StageTag(tier), (g_en[tier] ? "เปิด" : "ปิด"));
   PrintFormat("🔘 %s", g_last_status);
   DrawTierButtons();
}

// แสดง / ซ่อนป้าย (ซ่อน = ทุก TF)
void SetLabelVisible(string name, bool vis) {
   long tf = vis ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   if(ObjectGetInteger(0, name, OBJPROP_TIMEFRAMES) != tf) ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tf);
}

// จัดป้ายที่มองเห็นไม่ให้ซ้อนกัน (ตามขนาดตัวอักษรจริงบนจอ) — จัดใหม่เมื่อซูม / เลื่อน / สเกลราคา / มีไม้ใหม่ / ป้ายเปลี่ยน
//   1) ป้ายไม้ (Tick Replay + ไม้จริง): เรียงตามเวลา, ทับกัน → เลื่อนขึ้น/ลงทีละแถว + เส้นโยงจากจุดเข้าไม้
//   2) ป้ายบนแท่ง: กลุ่มละ 1 แท่ง 1 ฝั่ง (ติดแท่งออกไป) จัดแท่งใหม่ก่อน, เลื่อนออกจากแท่งได้ไม่เกิน LAYOUT_MAX_SHIFT แถว
//      ไม่มีที่ว่าง → ซ่อนป้ายนั้น (ค่าทั้งหมดดูได้ในกล่องรายละเอียดแท่ง)
void LayoutLabels() {
   if(!g_draw) return;
   long   first = ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   long   wb    = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   long   hpx   = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   long   wpx   = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   double pmax  = ChartGetDouble(0, CHART_PRICE_MAX);
   double pmin  = ChartGetDouble(0, CHART_PRICE_MIN);
   string sig   = StringFormat("%I64d|%I64d|%I64d|%I64d|%.5f|%.5f|%d|%d|%d|%d|%.5f|%.5f", first, wb, hpx, wpx, pmax, pmin,
                               ArraySize(g_rt), ArraySize(g_marks), ArraySize(g_zl_names), g_lbl_ver, g_bar0_hi, g_bar0_lo);
   if(sig == g_lay_sig) return;
   g_lay_sig = sig;
   if(hpx <= 0 || pmax <= pmin) return;
   datetime t_vis  = iTime(_Symbol, PERIOD_CURRENT, (int)first);
   if(t_vis == 0) return;
   datetime t_from = t_vis - (datetime)(PeriodSeconds(PERIOD_CURRENT) * 60);   // ป้ายทางซ้ายที่ข้อความยาวเข้ามาในจอ
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

   // 4) ป้ายบนแท่ง (TF ของ Z) + ป้าย TF ใหญ่ ในช่วงที่มองเห็น — กลุ่มละไม่เกิน 3 ป้าย เรียงจากติดแท่งออกไป
   if(ArraySize(g_zl_names) == 0) return;
   MqlRates zb[];
   datetime t_l = t_vis - (datetime)PeriodSeconds(InpZ_Timeframe);
   datetime t_r = TimeCurrent() + (datetime)PeriodSeconds(InpZ_Timeframe);
   int got = CopyRates(_Symbol, InpZ_Timeframe, t_l, t_r, zb);
   if(got <= 0) return;
   double off = PtsToPrice(InpBarZOffset_Pts);
   int    ng  = 0;
   datetime gt[];
   bool     gup[];
   double   gbase[];
   long     gkey[];
   string   gi[];   // ชื่อป้ายของกลุ่ม g = gi[g * 3 + m]
   for(int q = 0; q < got; q++) {
      string ts = IntegerToString((long)zb[q].time);
      bool   live = (q == got - 1 && zb[q].time == CurrentZBarTime());
      double hi = (live && g_bar0_hi > 0.0) ? g_bar0_hi : zb[q].high;
      double lo = (live && g_bar0_lo > 0.0) ? g_bar0_lo : zb[q].low;
      for(int u = 0; u < 2; u++) {   // u = 0 เหนือแท่ง / 1 ใต้แท่ง
         string i0 = OBJ_PREFIX + (u == 0 ? "FL_B_" : "FL_S_") + ts;
         string i1 = OBJ_PREFIX + (u == 0 ? "ZL_S_" : "ZL_B_") + ts;
         string i2 = OBJ_PREFIX + (u == 0 ? "ZM_S_" : "ZM_B_") + ts;
         bool   hz = ObjectFind(0, i1) >= 0;
         if(!hz && ObjectFind(0, i0) < 0) continue;
         ArrayResize(gt, ng + 1); ArrayResize(gup, ng + 1); ArrayResize(gbase, ng + 1); ArrayResize(gkey, ng + 1); ArrayResize(gi, (ng + 1) * 3);
         gt[ng] = zb[q].time; gup[ng] = (u == 0); gbase[ng] = (u == 0) ? hi + off : lo - off;
         gkey[ng] = (hz ? (long)4.0e9 : (long)0) + (long)zb[q].time;   // ป้าย Z ก่อน, ป้ายลอยตัวทีหลัง, แท่งใหม่ก่อน
         gi[ng * 3] = i0; gi[ng * 3 + 1] = i1; gi[ng * 3 + 2] = i2;
         ng++;
      }
   }
   if(InpShowHTF && g_htf_ok) {   // ป้าย TF ใหญ่: กึ่งกลางแท่ง TF ใหญ่ เหนือ High / ใต้ Low (จัดหลังป้าย Z ก่อนป้ายลอยตัว)
      MqlRates hb[];
      long     per_h = PeriodSeconds(InpHTF);
      int      gh    = CopyRates(_Symbol, InpHTF, t_l - (datetime)per_h, t_r, hb);
      for(int q = 0; q < gh; q++) {
         string ts = IntegerToString((long)hb[q].time);
         for(int u = 0; u < 2; u++) {
            string i0 = OBJ_PREFIX + (u == 0 ? "HT_U_" : "HT_D_") + ts;
            if(ObjectFind(0, i0) < 0) continue;
            ArrayResize(gt, ng + 1); ArrayResize(gup, ng + 1); ArrayResize(gbase, ng + 1); ArrayResize(gkey, ng + 1); ArrayResize(gi, (ng + 1) * 3);
            gt[ng] = hb[q].time + (datetime)(per_h / 2); gup[ng] = (u == 0);
            gbase[ng] = (u == 0) ? hb[q].high + off : hb[q].low - off;
            gkey[ng]  = (long)2.0e9 + (long)hb[q].time;
            gi[ng * 3] = i0; gi[ng * 3 + 1] = ""; gi[ng * 3 + 2] = "";
            ng++;
         }
      }
   }
   // เรียงความสำคัญจากมากไปน้อย
   for(int a = 1; a < ng; a++) {
      int b = a;
      while(b > 0 && gkey[b - 1] < gkey[b]) {
         datetime t0 = gt[b]; gt[b] = gt[b - 1]; gt[b - 1] = t0;
         bool u0 = gup[b]; gup[b] = gup[b - 1]; gup[b - 1] = u0;
         double p0 = gbase[b]; gbase[b] = gbase[b - 1]; gbase[b - 1] = p0;
         long k0 = gkey[b]; gkey[b] = gkey[b - 1]; gkey[b - 1] = k0;
         for(int m = 0; m < 3; m++) { string s0 = gi[b * 3 + m]; gi[b * 3 + m] = gi[(b - 1) * 3 + m]; gi[(b - 1) * 3 + m] = s0; }
         b--;
      }
   }
   for(int g = 0; g < ng; g++) {
      int x = 0, y = 0;
      bool onscreen = ChartTimePriceToXY(0, 0, gt[g], gbase[g], x, y);
      double cursor = y;
      bool   hide   = !onscreen;
      for(int m = 0; m < 3; m++) {
         string nm2 = gi[g * 3 + m];
         if(nm2 == "" || ObjectFind(0, nm2) < 0) continue;
         if(hide) { SetLabelVisible(nm2, false); continue; }
         uint tw = 0, th = 0;
         TextSetFont(ObjectGetString(0, nm2, OBJPROP_FONT), -10 * (int)ObjectGetInteger(0, nm2, OBJPROP_FONTSIZE));
         TextGetSize(ObjectGetString(0, nm2, OBJPROP_TEXT), tw, th);
         double w  = (double)tw + 6.0, h = (double)th + 1.0;
         double xa = x - w / 2.0, xb = x + w / 2.0;
         bool   ok = false;
         for(int sh = 0; sh <= LAYOUT_MAX_SHIFT; sh++) {
            double ya = gup[g] ? cursor - (sh + 1) * h : cursor + sh * h;
            double yb = ya + h;
            bool   hit = false;
            for(int q = 0; q < placed && !hit; q++)
               hit = (xa < x1s[q] && xb > x0s[q] && ya < y1s[q] && yb > y0s[q]);
            if(hit) continue;
            double ay = gup[g] ? yb : ya;   // ขอบที่ยึด (ANCHOR_LOWER / ANCHOR_UPPER)
            double np = gbase[g] - (ay - y) * ppx;
            if(MathAbs(ObjectGetDouble(0, nm2, OBJPROP_PRICE) - np) > _Point) ObjectSetDouble(0, nm2, OBJPROP_PRICE, np);
            if((datetime)ObjectGetInteger(0, nm2, OBJPROP_TIME) != gt[g]) ObjectSetInteger(0, nm2, OBJPROP_TIME, gt[g]);
            SetLabelVisible(nm2, true);
            ArrayResize(x0s, placed + 1); ArrayResize(x1s, placed + 1); ArrayResize(y0s, placed + 1); ArrayResize(y1s, placed + 1);
            x0s[placed] = xa; x1s[placed] = xb; y0s[placed] = ya; y1s[placed] = yb;
            placed++;
            cursor = gup[g] ? ya : yb;
            ok = true;
            break;
         }
         if(!ok) { hide = true; SetLabelVisible(nm2, false); }   // ซ่อนป้ายนี้ + ป้ายที่อยู่ไกลแท่งกว่าในกลุ่มเดียวกัน
      }
   }
}

//====================================================================
// 🔎 กล่องรายละเอียดแท่ง (มุมซ้ายล่าง เหนือปุ่ม T2-T4): ชี้เมาส์ที่แท่ง → ค่าทั้งหมดของแท่งนั้น
//   เหนือกลางแท่ง = ฝั่ง SELL (Z ขึ้น), ใต้กลางแท่ง = ฝั่ง BUY (Z ลง) | ไม่ได้ชี้ = แท่งปัจจุบัน ฝั่งที่ Z สูงกว่า
//====================================================================
void PanelAdd(string &L[], color &C[], string text, color clr) {
   int n = ArraySize(L);
   ArrayResize(L, n + 1);
   ArrayResize(C, n + 1);
   L[n] = text;
   C[n] = clr;
}

bool BuildPanel(datetime bar, string &L[], color &C[]) {
   ArrayResize(L, 0);
   ArrayResize(C, 0);
   int n = InpZ_Period;
   MqlRates r[];
   double   c[];
   int got = CopyRates(_Symbol, InpZ_Timeframe, bar, n + STREAK_MAX, r);
   if(got < n + 1 || r[got - 1].time != bar) return false;
   ArrayResize(c, got);
   for(int i = 0; i < got; i++) c[i] = r[i].close;
   int    j  = got - 1;
   double zr[4];
   double zs[4];
   if(!BarZOHLC(r, c, j, zr, zs)) return false;
   bool   live = (bar == CurrentZBarTime());
   double sma = 0.0, sd = 0.0;
   double fz  = SmaSdAt(c, j, r[j].open, sma, sd) ? (r[j].open - sma) / sd : 0.0;
   double up  = MathMax(zr[1], zs[1]), dn = MathMax(-zr[2], -zs[2]);
   int    side = (g_pn_side >= 0) ? g_pn_side : (up >= dn ? 0 : 1);
   int    dir  = (side == 0) ? -1 : 1;
   int    pk, cl;
   ZStreaks(r, c, j, side, pk, cl);
   string cls  = live ? "ตอนนี้" : "ปิด";

   PanelAdd(L, C, StringFormat("แท่ง %s (%s)%s  ·  ฝั่ง %s  ·  Z สูงสุด %+.2f", TimeToString(bar, TIME_DATE|TIME_MINUTES),
                               StringSubstr(EnumToString(InpZ_Timeframe), 7), (live ? " กำลังเดิน" : ""),
                               (side == 0 ? "SELL (Z ขึ้น)" : "BUY (Z ลง)"), (side == 0 ? up : -dn)), InpClrPanelHead);
   PanelAdd(L, C, StringFormat("Z_reg    เปิด %+.2f    สูง %+.2f    ต่ำ %+.2f    %s %+.2f", zr[0], zr[1], zr[2], cls, zr[3]), InpClrPanelText);
   PanelAdd(L, C, StringFormat("Z_SMA   เปิด %+.2f    สูง %+.2f    ต่ำ %+.2f    %s %+.2f    Z_float %+.2f", zs[0], zs[1], zs[2], cls, zs[3], ZFloat(dir, fz)), InpClrPanelText);

   BarSpeed bs;
   if(SpeedOf(bar, bs)) {
      SideStat st;
      st = bs.sd[side];
      double rate = SpeedRate(st.sp[2], 0);
      PanelAdd(L, C, StringFormat("เร็ว (Z ตัวใดก็ได้ จาก %.1f)    %s%s", InpSpeedFromZ, SpeedLong(st.sp[2]),
                                  (rate >= 0.0 ? StringFormat("    อัตรา %.3f Z/วิ", rate) : "")), InpClrPanelText);
      PanelAdd(L, C, StringFormat("      แยกตัว ถึง %.1f:    Z_reg %s    Z_SMA %s%s", InpT2_Z, SpeedCell(st.sp[0], 0), SpeedCell(st.sp[1], 0),
                                  (bs.fresh ? "" : "    (เริ่มนับกลางแท่ง)")), InpClrPanelText);
      string now_run = live ? StringFormat("    ตอนนี้ %s", ShortSec(ZoneRunSec(g_trk_live.tr[side], g_last_tick_msc))) : "";
      PanelAdd(L, C, StringFormat("ค้าง Z ≥ %.1f    นานสุด %s    รวมในแท่ง %s%s", InpZoneZ, ShortSec(st.zone_max_ms / 1000),
                                  ShortSec(st.zone_cum_ms / 1000), now_run), InpClrPanelText);
      PanelAdd(L, C, StringFormat("K2 (ทำยอดใหม่ใน %d วิ ก่อนยอดล่าสุด)    %d ครั้ง    สูงสุดในแท่ง %d", InpK2_Window_Sec, st.k2, st.k2_max), InpClrPanelText);
   }
   else PanelAdd(L, C, "เร็ว / ค้าง / K2:  ไม่มีข้อมูล tick (เก่ากว่าช่วง Tick Replay)", InpClrBarZOther);
   PanelAdd(L, C, StringFormat("แท่งติดกัน    ยอด Z ≥ %.1f = %d แท่ง    %s Z ≥ %.1f = %d แท่ง%s", InpZoneZ, pk, cls, InpZoneZ, cl,
                               (live ? "  (แท่งนี้ยังไม่ปิด)" : "")), InpClrPanelText);

   if(g_htf_ok) {
      double hzr, hzs;
      datetime hb;
      int ht = HTFTierAt(bar, side, hzr, hzs, hb);
      if(hb > 0)
         PanelAdd(L, C, StringFormat("%s แท่ง %s (ทั้งแท่ง)    %s    Z_reg %+.2f    Z_SMA %+.2f", HTFName(), TimeToString(hb, TIME_MINUTES),
                                     (ht > 0 ? StageTag(ht) : "ไม่ถึง T2"), hzr, hzs), (ht > 0 ? HTFColor(ht) : InpClrPanelText));
   }
   int k = BarRecFind(bar, side);
   if(k >= 0) {
      color oc = (g_bo[k].result == BO_REV) ? clrLimeGreen : (g_bo[k].result == BO_CONT ? clrTomato : InpClrPanelText);
      string res = BarResultName(g_bo[k].result);
      if(g_bo[k].result != BO_WAIT && g_bo[k].result != BO_UNC)
         res += StringFormat(" ใน %.1f นาที", (double)(g_bo[k].res_msc - g_bo[k].st.ext_msc) / 60000.0);
      PanelAdd(L, C, StringFormat("ผล %d นาทีหลังยอด (Replay)    %s    ถอยสุด %.2fσ    ทะลุยอดสุด %+.0f จุด",
                                  InpOutcomeMin, res, g_bo[k].max_rev, g_bo[k].max_cont), oc);
   }
   PanelAdd(L, C, StringFormat("ป้ายแถว 2:  เร็ว = วิ จาก Z %.1f ถึง %.1f · ค้าง = ค้าง Z ≥ %.1f นานสุด · K2 · ติด = แท่งติดกัน · * = นับจากเปิดแท่ง",
                               InpSpeedFromZ, InpT2_Z, InpZoneZ), InpClrBarZOther);
   return true;
}

void DrawBarPanel(bool force) {
   if(!g_draw || !InpShowBarPanel) return;
   datetime bar = (g_pn_bar != 0) ? g_pn_bar : CurrentZBarTime();
   string L[];
   color  C[];
   if(!BuildPanel(bar, L, C)) return;
   string joined = "";
   for(int i = 0; i < ArraySize(L); i++) joined += L[i] + "\n";
   if(!force && joined == g_pn_text) return;
   g_pn_text = joined;

   int  fs = MathMax(6, InpPanelFontSize);
   uint maxw = 0, th = 0;
   TextSetFont("Arial", -10 * fs);
   for(int i = 0; i < ArraySize(L); i++) {
      uint w = 0, h = 0;
      TextGetSize(L[i], w, h);
      if(w > maxw) maxw = w;
      if(h > th) th = h;
   }
   int pad = 6, lh = (int)th + 3, nl = ArraySize(L);
   int wbox = (int)maxw + 2 * pad, hbox = nl * lh + 2 * pad, ybot = 64;
   string bg = PANEL_PREFIX + "BG";
   if(ObjectFind(0, bg) < 0) {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, ybot + hbox);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, wbox);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, hbox);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, InpClrPanelBg);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, InpClrPanelHead);
   for(int i = 0; i < 20; i++) {
      string nm = PANEL_PREFIX + "L" + IntegerToString(i);
      if(i >= nl) { if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm); continue; }
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetString(0,  nm, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fs);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10 + pad);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ybot + hbox - pad - i * lh);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, C[i]);
      ObjectSetString(0,  nm, OBJPROP_TEXT, L[i]);
   }
}

// ชี้เมาส์ → เลือกแท่ง (TF ของ Z) + ฝั่งตามตำแหน่งราคาเทียบกลางแท่ง
void PanelHover(int x, int y) {
   int      sub = 0;
   datetime t   = 0;
   double   p   = 0.0;
   if(!ChartXYToTimePrice(0, x, y, sub, t, p) || sub != 0 || t <= 0) return;
   datetime cur = CurrentZBarTime();
   datetime bar = BarStartOf(t);
   if(bar > cur) bar = cur;
   int sh = iBarShift(_Symbol, InpZ_Timeframe, bar, true);
   if(sh < 0) return;
   double hi = iHigh(_Symbol, InpZ_Timeframe, sh), lo = iLow(_Symbol, InpZ_Timeframe, sh);
   int      side = (p >= (hi + lo) / 2.0) ? 0 : 1;
   datetime keep = (bar == cur) ? 0 : bar;
   if(keep == g_pn_bar && side == g_pn_side) return;
   g_pn_bar  = keep;
   g_pn_side = side;
   DrawBarPanel(false);
   ChartRedraw(0);
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
int OnInit() {
   if(InpZ_Period < 2) { Print("❌ Period ต้องอย่างน้อย 2"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpBarZBars < 1 || InpBarZBars > 20000) { Print("❌ InpBarZBars ต้องอยู่ระหว่าง 1-20000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpReplayDays < 1 || InpReplayDays > 60) { Print("❌ InpReplayDays ต้องอยู่ระหว่าง 1-60"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpT2_Z <= 0.0 || InpT3_Z < InpT2_Z || InpT4_Z < InpT3_Z ||
      InpT2_Sec < 0 || InpT3_Sec < 0 || InpNoNewExtEps < 0.0 || InpTierLotStep < 0.0 || InpSpeedFromZ < 0.0) {
      Print("❌ ค่า Z ระดับวิกฤต (ต้อง T2 ≤ T3 ≤ T4) / เวลาเฝ้า / Lot ต่อระดับ / จุดเริ่มจับความเร็ว Z ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLot <= 0.0) { Print("❌ Lot ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpStopDist_Pts <= 0.0 || InpSLPeak_Pts < 0.0 || InpExitBars < 0 || InpCounterMaxSL_Pts < 0.0 || InpTrendNearOpen_Pts < 0.0) {
      Print("❌ ระยะ Stop / SL / เพดาน SL / ระยะใกล้ราคาเปิด / จำนวนแท่งตัดจบ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSigmaFloorMult < 0.0 || InpNewsBlock_Min < 0 || InpNoTradeAfterOpen_Min < 0 ||
      InpNoTradeBeforeClose_Min < 0 || InpCloseBeforeClose_Min < 0) {
      Print("❌ ค่าพื้นตัวหาร / ช่วงข่าว / เวลาห้ามเข้าก่อน-หลังตลาด ไม่ถูกต้อง");
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
   long per_z = PeriodSeconds(InpZ_Timeframe), per_h = PeriodSeconds(InpHTF);
   g_htf_ok   = (per_h > per_z && per_z > 0 && per_h % per_z == 0 && per_h <= DAY_SEC);
   if(InpShowHTF && !g_htf_ok)
      PrintFormat("⚠️ InpHTF (%s) ต้องใหญ่กว่าและหารลงตัวด้วย TF ของ Z (%s) และไม่เกิน D1 — ปิดกรอบ TF ใหญ่",
                  EnumToString(InpHTF), EnumToString(InpZ_Timeframe));
   g_htf_bar  = 0;
   g_barz_bar = 0;
   ArrayResize(g_zl_names, 0);
   ArrayResize(g_zl_times, 0);
   TrackerReset(g_trk_live);
   ArrayResize(g_spd_hist, 0);
   ArrayInitialize(g_prev_pk, 0);
   ArrayInitialize(g_prev_cl, 0);
   g_lbl_ver = 0; g_pn_bar = 0; g_pn_side = -1; g_pn_text = "";

   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   g_bar_changed   = false;
   g_last_tick_msc = 0;
   g_zc.ok         = false;
   ReplayReset();
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_next_try       = 0;
   g_news_loaded    = 0;
   g_news_ok        = false;
   g_prev_close_zr  = 0.0;
   g_prev_close_zs  = 0.0;
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
   g_ord_retry = 0;

   RefreshNews(ServerNow());
   TierEnableInit();
   g_lay_sig = "";

   ObjectsDeleteAll(0, OBJ_PREFIX);
   LoadEntryMarksFromHistory();
   if(g_draw && InpShowBarPanel) ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
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
   TrackTick(g_trk_live, g_z_reg, g_z_sma, tk.bid, g_sma_sd, g_last_tick_msc);   // สถิติ tick ของแท่ง (ตามเวลาของ tick)

   UpdateLiveZLabel(tk.bid);

   int ts = GetTimeState(ServerNow());
   if(ts == TS_CLOSING) {
      CloseAllPositions();
      return;
   }
   if(ts != TS_CLOSED) ManageOrders(ServerNow(), ts);   // ยกเลิกออเดอร์รอที่หมดอายุ / ตัดจบทันที tick แรกของแท่งถัดไป
   LiveSignalStep(g_last_tick_msc, ts, tk.bid, tk.ask, true);
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ / ยกเลิกออเดอร์รอที่หมดอายุ / ตัดจบตามเวลา
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManageOrders(now, ts);

   // 2. ยิงเมื่อครบเวลาเฝ้า แม้ไม่มี Tick เข้า (ราคา/Z ยังเป็นค่าล่าสุด)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   zok = (bid > 0.0 && ask > 0.0 && UpdateZ(bid));
   if(zok && ts != TS_CLOSING) LiveSignalStep(MathMax(g_last_tick_msc, (long)now * 1000), ts, bid, ask, false);

   // 3. อัปเดตการแสดงผล
   if(g_draw) {
      UpdateZLines();
      UpdateBarZLabels();
      UpdateHTFMarks();
      UpdateEntryMarks();
      ReplayStep();
      LayoutLabels();
      DrawBarPanel(false);
      LoadNewsHistory();
      if(bid > 0.0) UpdateLiveZLabel(bid);
      UpdateDashboard(ts, now);
      ChartRedraw(0);   // ให้วัตถุแสดงผลแม้ช่วงที่ไม่มี Tick เข้า
   }
}

// คลิกปุ่ม T2-T4 → เปิด/ปิดระดับ | ชี้เมาส์ → กล่องรายละเอียดแท่ง | เลื่อน/ซูม/ย่อขยายกราฟ → จัดตำแหน่งป้ายใหม่ทันที
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BTN_PREFIX) == 0) {
      ToggleTier((int)StringToInteger(StringSubstr(sparam, StringLen(BTN_PREFIX))));
      ChartRedraw(0);
      return;
   }
   if(id == CHARTEVENT_MOUSE_MOVE) {
      if(g_draw && InpShowBarPanel) PanelHover((int)lparam, (int)dparam);
      return;
   }
   if(id != CHARTEVENT_CHART_CHANGE || !g_draw) return;
   LayoutLabels();
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
   if(!IsOurDeal(trans.deal, DEAL_ENTRY_OUT)) return;
   WatchReset(g_wsell);   // ไม้ปิด → ล้างการเฝ้าทั้ง 2 ฝั่ง (รอสัญญาณใหม่)
   WatchReset(g_wbuy);
}
//+------------------------------------------------------------------+
