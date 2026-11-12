//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Fast Mean-Reversion Z-Score EA for XAUUSD (Indicator v8.82)  |
//+------------------------------------------------------------------+
//
// 🎯 นิยามระบบ (v14)
//  ค่า Z ที่สุดขั้วเกินจริงมักถูกดีดกลับ → 3 ชุดระบบอิสระ: T2-T4 (Stop 2 ขา) / T5 (Market สวนตอนแท่งใหม่) / S2 (สวนที่ไส้)
//  ชุดต่างกันเปิดซ้อนกันได้ แต่ห้ามซ้อนในชุดเดียวกัน (ชุดเดิมยังไม่จบ = ชุดนั้นไม่หาสัญญาณใหม่)
//  (ประวัติการเปลี่ยนแปลงทุกเวอร์ชันอยู่ใน README.md)
//
// 📐 Z-Score (TF ของ Z, 20 แท่ง, รวมแท่งปัจจุบันที่ราคา Bid)
//  • Z_reg = (ราคา − เส้นถดถอยเชิงเส้น) / max(StdDev รอบเส้นถดถอย, 0.5 × StdDev ของส่วนต่างราคาต่อแท่ง)
//  • Z_SMA = (ราคา − SMA20) / StdDev20
//
// 📋 ชุด T2-T4 — ตรวจ T4 → T3 → T2, เกณฑ์เดียวกันทั้ง SELL (+Z) / BUY (−Z), เปิด/ปิดแต่ละระดับด้วยปุ่มบนกราฟ
//  • T4: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > 3.5 + ไม่มียอดราคาใหม่ 2 วิ (Lot 0.04)
//  • T3: Z ตัวใดตัวหนึ่ง > 3.0 + ไม่มียอดราคาใหม่ 2 วิ (Lot 0.03)
//  • T2: แท่งลอย Z_float > 1.8 + Z ตัวใดตัวหนึ่ง > 2.5 + ไม่มียอดราคาใหม่ 5 วิ (Lot 0.02) (v14.80)
//    Z_float = (ราคาเปิดแท่ง − SMA ตอนเปิดแท่ง) ÷ SD20 | ระดับที่ปิดอยู่ = ข้ามไปตรวจระดับถัดลงมา
//  • ยอดราคาใหม่ (v14.80): Bid ทำ High (SELL) / Low (BUY) เกินจุดอ้างอิงล่าสุด ≥ 1,000 จุด → นับเวลาใหม่ + ย้ายจุดอ้างอิง
//  • ระหว่างจับเวลา Z หลุดเกณฑ์ได้ (ไม่ยกเลิก, ใช้ระดับลึกสุดที่ไปถึง) — ยกเลิกเมื่อขึ้นแท่งใหม่
//    + การเฝ้าระดับ T2: Z ตัวใดตัวหนึ่งกลับถึง 0 (เส้นกลาง) → ยกเลิกแล้วรอสัญญาณใหม่
//  • ตัวกรองตอนวาง: เวลาตลาด (ห้ามเข้า 1 ชม.หลังเปิด / 1 ชม.ก่อนปิดสัปดาห์) + สเปรด | ข่าว = แสดงอย่างเดียว ไม่กรอง
//  • ครบเงื่อนไข → วาง Stop Order 2 ตัว ห่างจากราคาสัญญาณฝั่งละ 1,000 จุด (Lot ตามระดับทั้งคู่, ไม่ใช่ OCO)
//    - สวนกลับ: สัญญาณ SELL (Z ขึ้น) = Sell Stop ที่ Bid − 1,000, SL = High ของแท่ง ณ ตอนสัญญาณ + 500 (ห่างราคาเข้าไม่เกิน 5,000)
//    - ตามน้ำ : สัญญาณ SELL = Buy Stop ที่ Ask + 1,000, SL คงที่ 5,000 จุดจากราคาเข้า (v14.80)
//    - Stop ที่ยังไม่ถูกเกี่ยวหมดอายุ 15 นาที | เข้าช่วงห้ามเข้าก่อนปิดสัปดาห์ → ยกเลิก
//
// 📋 ชุด T5 (v14.80): ระหว่างแท่ง Z ตัวใดตัวหนึ่งเคยแตะ > 4.0 (ไม่นับเวลา) → เปิดแท่งใหม่ Market สวนกลับทันที
//    Lot 0.05, SL คงที่ 5,000 | ไม่ต่อคิวชุดอื่น, ถือได้ทีละ 1 ไม้ | ติดตัวกรองลองใหม่ได้ 60 วิแรกของแท่ง | แตะทั้ง 2 ฝั่ง = ใช้ฝั่งล่าสุด
//
// 📋 ชุด S2 (v14.80, จาก Z3 EA): แท่งปิดล่าสุด Z ตัวใดตัวหนึ่งที่ High > 2.5 → ราคาเข้าไส้บน [max(Open, Close), High] = สแตนบาย
//    → Bid ไม่ทำ High ใหม่ของแท่งปัจจุบัน 10 วิ + High แท่งปัจจุบัน < High แท่งปิดล่าสุด → SELL Market (BUY กลับทิศ)
//    SL = High แท่งปัจจุบัน + สเปรด (ต่ำสุด 500, เกิน 3,000 = ยกเลิก) | TP = 2 × ระยะ SL | ออกด้วย TP / SL เท่านั้น (v14.90)
//    ราคาขึ้นเกิน High แท่งปิดล่าสุด = ยกเลิกทั้งแท่ง | ครั้งเดียวต่อแท่ง, ทีละ 1 ไม้, Lot 0.02
//
// 📋 ทางออกชุด T2-T4 / T5 (ไม่มี TP)
//  • ตัดจบที่ราคาปิดของแท่งที่ 2 หลังแท่งที่ออเดอร์ถูกเกี่ยว (= tick แรกของแท่งถัดไป)
//  • เกราะกำไร 3 ขั้น: กำไรสูงสุด 5,000 → SL ทุน +1,500 / 10,000 → +5,000 / 20,000 → +10,000 (ขยับทางเดียว)
//  • T2-T4 ถูกเกี่ยวทั้ง 2 ขา (v14.90): ขาแรกปิดทันที, ขาที่ 2 SL = ราคา Stop ของขาแรก (แล้วใช้เกราะ 3 ขั้น + ตัดจบ 2 แท่ง)
//  • โหมดวิ่งยาว (v14.90, T2-T4 ที่เกี่ยวฝั่งเดียว + T5): กำไรสูงสุดถึง 5,000 → SL ทุน +1,500, ตัดจบเลื่อนเป็น 4 แท่ง,
//    ลบ Stop อีกฝั่งที่รอ (T2-T4) → กำไรสูงสุดถึง 10,000 → ไล่จี้ SL ห่างราคา 8,000 (แทนเกราะขั้น 2-3)
//  • ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//
// 🔘 1 ชุด/แท่ง (v14.91, เปิดปิดได้ด้วย InpOneSetPerBar / ปุ่ม "1/แท่ง"): ชุด T2-T4 วางได้ 1 ครั้งต่อแท่ง (นับตอนวางชุด)
//    T5 (เปิดตอนแท่งใหม่) และ S2 (ครั้งเดียวต่อแท่ง) เป็น 1 ครั้ง/แท่งอยู่แล้วโดยการออกแบบ
//
// ⏱️ ค่าชี้วัดการกระชาก (บันทึก / แสดงผลอย่างเดียว ไม่มีผลกับการเทรด)
//  • เร็ว: จากครั้งล่าสุดที่ Z ตัวใดตัวหนึ่งตัดขึ้นผ่าน 1.5 ในแท่ง → ถึง 2.5 / 3.0 / 3.5 (วินาที, * = นับจากเวลาเปิดแท่ง) + อัตรา Z/วิ
//  • K2: จำนวนครั้งที่ทำยอดใหม่ของแท่ง ภายใน 60 วิก่อนยอดล่าสุด
//  • แท่งสด = เวลาจริงจาก tick ที่ EA เห็น, แท่งย้อนหลัง = จาก tick ของ Tick Replay
//  • ป้ายบนแท่ง 2 แถว + จัดตำแหน่งไม่ให้ซ้อน (ไม่มีที่ = ซ่อน) | ชี้เมาส์ที่แท่ง = กล่องรายละเอียดมุมซ้ายล่าง (Z เปิด / สูง / ต่ำ / ปิด)
//
// 🧪 Tick Replay (บนกราฟ, ไม่ใช่ Strategy Tester)
//  • เล่นซ้ำ tick จริงย้อนหลังด้วยกติกาเดียวกับ EA → มาร์กบนกราฟ + สรุปบน Dashboard
//  • CSV ไม้ (7LCEA_Replay_<symbol>.csv) + CSV ชุด (7LCEA_Sets_<symbol>.csv): ค่าตอนสัญญาณ (Z, Z_float, เร็ว, K2) + ผล + ระยะกำไรระหว่างถือ
//  (เส้นบริบท VWAP / Keltner / TF ใหญ่ / วันก่อน / EMA ยาว แยกไปอยู่ใน Indicators/Seven_Lines_Context_Ind.mq5)
//
// ⚡ การประหยัด CPU
//  • Z: แคชผลรวมของแท่งที่ปิดแล้ว คำนวณใหม่เฉพาะตอนขึ้นแท่งใหม่ (ต่อ Tick ไม่กี่บรรทัดคณิต)
//  • งานเทรด (เกราะ / ตัดจบ / หมดอายุ / ยิง) ทำต่อ Tick + Timer 200 ms ก่อนงานแสดงผลเสมอ
//    เวลา = เวลา tick ล่าสุด + เวลาที่ผ่านไปตามนาฬิกาในเครื่อง (แม่นแม้ tick ห่าง)
//  • งานแสดงผลทุก 1 วินาที — ช่วงร้อน (กำลังเฝ้าสัญญาณ) ข้าม Replay / จัดป้าย / กล่องรายละเอียด / ข่าว
//  • Tick Replay เล่นได้ไม่เกิน 150 ms ต่อรอบ (ที่เหลือเล่นรอบถัดไป)
//  • Dashboard เขียนเฉพาะเมื่อข้อความเปลี่ยน, ไม่วาดอะไรใน Tester แบบไม่เปิด Visual
//
#property copyright   "Commander's Quant System"
#property version     "14.91"
#property description "สวนกลับค่า Z ผิดปกติ 3 ชุดอิสระ (T2-T4 / T5 / S2) สำหรับ XAUUSD (บัญชี Hedging)"

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
input bool            InpEnableT5          = true;       // เปิดใช้ T5 (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ)
input bool            InpOneSetPerBar      = true;       // 1 แท่ง (TF ของ Z) วางชุด T2-T4 ได้ 1 ครั้ง (ค่าเริ่มต้น — สลับได้ด้วยปุ่ม "1/แท่ง")
input double          InpT2_Z              = 2.50;       // T2: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ (ต้องผ่านแท่งลอยก่อน)
input int             InpT2_Sec            = 5;          // T2: ยิงเมื่อไม่มียอดราคาใหม่ครบกี่วินาที
input double          InpT3_Z              = 3.00;       // T3: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ (ไม่ต้องลอย)
input int             InpT3_Sec            = 2;          // T3: ยิงเมื่อไม่มียอดราคาใหม่ครบกี่วินาที
input double          InpT4_Z              = 3.50;       // T4: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้ (ไม่ต้องลอย)
input int             InpT4_Sec            = 2;          // T4: ยิงเมื่อไม่มียอดราคาใหม่ครบกี่วินาที (0 = ทันที)
input double          InpT5_Z              = 4.00;       // T5: Z ตัวใดตัวหนึ่งเคยแตะ > ค่านี้ในแท่ง → เปิดแท่งใหม่ Market สวนกลับ (ชุดอิสระ ไม่ต่อคิว)
input int             InpT5_RetrySec       = 60;         // T5: เปิดแท่งใหม่แล้วติดตัวกรอง → ลองใหม่ได้ภายในกี่วินาทีแรกของแท่ง
input double          InpT5_SL_Pts         = 5000.0;     // T5: SL คงที่ห่างจากราคาเข้า (จุด)
input bool            InpFloatFilter       = true;       // T2 ต้องเป็นแท่งลอยตัว: ราคาเปิดแท่งพ้นเส้น SMA ตอนเปิดแท่ง (SELL เหนือ / BUY ใต้)
input double          InpFloatMin          = 1.80;       // T2 ทำงานเมื่อแท่งลอย Z_float > ค่านี้ (หน่วย SD20, 0 = แค่ราคาเปิดพ้น SMA)
input double          InpNoNewExt_Pts      = 1000.0;     // T2-T4: Bid ต้องทำยอดใหม่เกินจุดอ้างอิงล่าสุดอย่างน้อยกี่จุด จึงนับเวลาใหม่
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 1.1 S2 สวนที่ไส้แท่งปิดล่าสุด (จาก Z3 EA, ชุดอิสระ) ==="
input bool            InpEnableS2          = true;       // เปิดใช้ S2 (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ)
input double          InpS2_PrevZ          = 2.50;       // S2: แท่งปิดล่าสุด Z ตัวใดตัวหนึ่งที่ High (SELL) / Low (BUY) > ค่านี้
input int             InpS2_NoNewSec       = 10;         // S2: ไม่มี High (SELL) / Low (BUY) ใหม่ของแท่งปัจจุบันครบกี่วินาที → ยิง
input double          InpS2_MinSL_Pts      = 500.0;      // S2: SL = High (SELL) / Low (BUY) แท่งปัจจุบัน ± สเปรด — ระยะต่ำสุด (จุด)
input double          InpS2_MaxSL_Pts      = 3000.0;     // S2: ระยะ SL เกินกี่จุด → ยกเลิกสัญญาณของแท่งนั้น (0 = ไม่จำกัด)
input double          InpS2_RR             = 2.0;        // S2: TP = กี่เท่าของระยะ SL (ออกด้วย TP / SL เท่านั้น)
input double          InpS2_Lot            = 0.02;       // S2: Lot

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot ฐาน (T2 = ฐาน + step = 0.02)
input double          InpTierLotStep       = 0.01;       // Lot เพิ่มต่อระดับ (T2 = ฐาน+step, T3 = +2·step, T4 = +3·step, T5 = +4·step) — S2 ใช้ InpS2_Lot
input double          InpStopDist_Pts      = 1000.0;     // Stop Order ห่างจากราคาสัญญาณฝั่งละกี่จุด (Buy Stop = Ask + / Sell Stop = Bid −)
input double          InpSLPeak_Pts        = 500.0;      // SL ฝั่งสวนกลับ = High (สัญญาณ SELL) / Low (สัญญาณ BUY) ของแท่ง ณ ตอนสัญญาณ ± ระยะนี้ (จุด)
input double          InpCounterMaxSL_Pts  = 5000.0;     // SL ฝั่งสวนกลับห่างจากราคาเข้าได้สูงสุดกี่จุด (รวม buffer แล้ว, 0 = ไม่จำกัด)
input double          InpTrendSL_Pts       = 5000.0;     // ฝั่งตามน้ำ: SL คงที่ห่างจากราคาเข้า (จุด)
input int             InpStopExpire_Min    = 15;         // Stop Order ที่ยังไม่ถูกเกี่ยว หมดอายุหลังวางกี่นาที
input int             InpExitBars          = 2;          // ตัดจบที่ราคาปิดของแท่งที่ N หลังแท่งที่ออเดอร์ถูกเกี่ยว (TF ของ Z)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์ (ต่อท้ายด้วยระดับ / C สวน, F ตาม / Z สุดขั้ว)

input group "=== 3. เกราะกำไร 3 ขั้น (ทุกขา รวม T5, วัดจากกำไรสูงสุด, SL ขยับทางเดียว) ==="
input double          InpLock1_Trig_Pts    = 5000.0;     // เกราะขั้น 1: กำไรสูงสุดถึงกี่จุด (0 = ปิดขั้นนี้)
input double          InpLock1_Pts         = 1500.0;     // เกราะขั้น 1: SL ไปที่ราคาเข้า + กี่จุด (ฝั่งกำไร)
input double          InpLock2_Trig_Pts    = 10000.0;    // เกราะขั้น 2: กำไรสูงสุดถึงกี่จุด (0 = ปิดขั้นนี้)
input double          InpLock2_Pts         = 5000.0;     // เกราะขั้น 2: SL ไปที่ราคาเข้า + กี่จุด
input double          InpLock3_Trig_Pts    = 20000.0;    // เกราะขั้น 3: กำไรสูงสุดถึงกี่จุด (0 = ปิดขั้นนี้)
input double          InpLock3_Pts         = 10000.0;    // เกราะขั้น 3: SL ไปที่ราคาเข้า + กี่จุด
input double          InpLongTrailStart_Pts = 10000.0;   // โหมดวิ่งยาว (T2-T4 เกี่ยวฝั่งเดียว / T5, เริ่มเมื่อกำไรสูงสุดถึงเกราะขั้น 1): กำไรสูงสุดถึงกี่จุด → ไล่จี้ (แทนเกราะขั้น 2-3)
input double          InpLongTrail_Pts     = 8000.0;     // โหมดวิ่งยาว: SL ไล่จี้ห่างราคากี่จุด
input int             InpLongExitBars      = 4;          // โหมดวิ่งยาว: ตัดจบที่ราคาปิดของแท่งที่ N หลังแท่งที่ถูกเกี่ยว
input double          InpTrailStep_Pts     = 100.0;      // ไล่จี้ (ไม้จริง): ขยับเมื่อดีขึ้นอย่างน้อยกี่จุด (ไม่เกิน 1 ครั้ง/วินาที)

input group "=== 4. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpNoTradeBeforeClose_Min = 60;    // ห้ามเข้าไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input int             InpNewsBlock_Min     = 5;          // ข่าว (แสดงอย่างเดียว ไม่กรอง): แถบก่อน / หลังเวลาข่าวออกกี่นาที
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าวที่แสดง

input group "=== 5. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowLiveZ         = true;       // แสดงป้ายค่า Z สด ณ ราคาปัจจุบัน
input int             InpLiveZFontSize     = 11;         // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;         // ระยะห่างป้าย Z สดจากขอบขวาของกราฟ (พิกเซล)
input bool            InpShowBarZ          = true;       // แสดงป้ายค่า Z บนแท่งที่ Z ถึงเกณฑ์
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย (สูงสุด 20,000)
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input bool            InpShowZSpeed        = true;       // ป้าย Z บนแท่ง: แถวที่ 2 = เร็ว / K2
input double          InpSpeedFromZ        = 1.50;       // ความเร็ว: เริ่มจับเมื่อ Z ตัวใดตัวหนึ่งตัดขึ้นผ่านค่านี้ (ครั้งล่าสุดในแท่ง)
input int             InpK2_Window_Sec     = 60;         // K2: นับครั้งที่ทำยอดใหม่ของแท่ง ภายในกี่วินาทีก่อนยอดล่าสุด
input bool            InpShowBarPanel      = true;       // กล่องรายละเอียดแท่ง (ชี้เมาส์ที่แท่ง → ค่าทั้งหมด, มุมซ้ายล่าง)
input int             InpPanelFontSize     = 9;          // ขนาดตัวอักษรกล่องรายละเอียดแท่ง
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กสัญญาณที่ถูกตัวกรองทิ้ง
input bool            InpReplayCSV         = true;       // Tick Replay: บันทึกค่าตอนสัญญาณ + ผล + ระยะกำไรระหว่างถือ ลง CSV (MQL5/Files)
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (แสดงอย่างเดียว ไม่กรอง, ใช้ไม่ได้ใน Tester)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium บนกราฟด้วย

input group "=== 6. สี ==="
input color           InpClrLiveSell       = clrOrangeRed;      // ป้าย Z สด: ถึงเกณฑ์ SELL
input color           InpClrLiveBuy        = clrDeepSkyBlue;    // ป้าย Z สด: ถึงเกณฑ์ BUY
input color           InpClrLiveNear       = clrGold;           // ป้าย Z สด: ใกล้เกณฑ์
input color           InpClrLiveNormal     = clrSilver;         // ป้าย Z สด: ปกติ
input color           InpClrBarZSell       = clrOrangeRed;      // ป้าย Z บนแท่ง: ฝั่ง SELL (เหนือแท่ง)
input color           InpClrBarZBuy        = clrDeepSkyBlue;    // ป้าย Z บนแท่ง: ฝั่ง BUY (ใต้แท่ง)
input color           InpClrBarZOther      = clrGray;           // ป้าย Z บนแท่ง: ถึงเกณฑ์ไม่ครบตามเงื่อนไขเข้าไม้
input color           InpClrBarZInfo       = clrKhaki;          // ป้ายบนแท่งแถวที่ 2: เร็ว / K2
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
const string LABEL_LIVE_Z   = "7LCEA_LIVE_Z";
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
   double ext_s;      // ค่าสุดขั้วของ Z_SMA ระหว่างเฝ้า (บันทึก / แสดงผล)
   double ext_px;     // จุดอ้างอิงยอดราคา (Bid): ทำยอดใหม่เกินจุดนี้ ≥ InpNoNewExt_Pts → นับเวลาใหม่
   long   last_new;   // เวลา (msc) ที่ทำยอดราคาใหม่ล่าสุด
   long   started;    // เวลา (msc) ที่เริ่มเฝ้า
   double start_px;   // ราคาตอนเริ่มเฝ้า
};

// S2: สถานะสวนที่ไส้ของแท่งปัจจุบัน — ใช้ร่วมกันทั้ง EA จริงและ Tick Replay
//   k 0 = ไส้บน (SELL) / 1 = ไส้ล่าง (BUY)
struct S2State {
   datetime bar;
   double   p_open, p_high, p_low, p_close;   // แท่งปิดล่าสุด
   double   p_zhi, p_zlo;      // Z ตัวที่สูงกว่าที่ High / ตัวที่ต่ำกว่าที่ Low ของแท่งปิดล่าสุด
   bool     ok;                // มีข้อมูลแท่งปิดล่าสุด
   double   hi, lo;            // High / Low ของแท่งปัจจุบัน (Bid)
   bool     sb[2];             // สแตนบาย
   bool     cancel[2];         // ราคาทะลุยอดแท่งปิดล่าสุด → ยกเลิกทั้งแท่ง
   long     last_new[2];       // เวลายอดใหม่ล่าสุดระหว่างสแตนบาย
   bool     done;              // เปิด S2 แล้วในแท่งนี้ (หรือทิ้งสัญญาณ)
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
   ZSpeed sp;           // ความเร็ว (Z ตัวใดก็ได้ = ตัวที่สูงกว่า)
   double peak_z;       // Z สูงสุดในแท่ง (ตัวที่สูงกว่า)
   int    k2;           // K2: จำนวนครั้งที่ทำยอดใหม่ของแท่ง ภายใน InpK2_Window_Sec ก่อนยอดล่าสุด
   int    k2_max;       // K2 สูงสุดในแท่ง
   double ext_px;       // ยอดราคาของแท่งจาก tick (SELL = High / BUY = Low)
};

// สถิติของแท่งหนึ่ง (เก็บไว้แสดงป้ายบนแท่ง / กล่องรายละเอียด): sd[0] = SELL, sd[1] = BUY
struct BarSpeed {
   datetime bar;
   bool     fresh;    // เห็น tick ตั้งแต่เปิดแท่ง (ไม่ได้เริ่มจับกลางแท่ง)
   SideStat sd[2];
};

// สถานะต่อเนื่องข้าม tick ของแต่ละฝั่ง: เวลาที่ทำยอดใหม่ (วงแหวนสำหรับ K2)
#define K2_RING 512
struct SideTrack {
   long   ring[K2_RING];
   int    head;
   int    cnt;
};

// ตัวติดตามต่อ tick (EA จริง 1 ตัว / Tick Replay 1 ตัว)
struct SpeedTracker {
   BarSpeed  cur;             // แท่งที่กำลังเดิน
   SideTrack tr[2];
};

// ค่า Z ของแท่ง (จาก OHLC) สำหรับป้ายบนแท่ง
struct BarView {
   datetime t;
   double   hi, lo, open;
   bool     ok[2];        // [0] = ที่ High (SELL), [1] = ที่ Low (BUY)
   double   zr[2];
   double   zs[2];
   double   fz;           // Z_float (+ = ราคาเปิดเหนือ SMA)
};

// แคชผลรวมของแท่งที่ปิดแล้ว (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct ZCache {
   bool   ok;
   double ref, sY, sXY, sYY, sD, sDD, last_close;
   double prev_zr, prev_zs;   // Z ตอนปิดแท่งล่าสุด
};

const double NEAR_ZONE = 0.5;   // ระยะ "ใกล้เกณฑ์" สำหรับสีป้าย Z
const int    SPEED_KEEP = 10000; // จำนวนแท่งสูงสุดที่เก็บสถิติ tick ของแท่ง

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
// --- ชุด T5 (EA จริง): แตะ > T5 ในแท่ง → เปิดแท่งถัดไป ---
int        g_t5_cur_dir     = 0;       // แท่งปัจจุบันแตะแล้ว: −1 = SELL (Z ขึ้น) / +1 = BUY / 0 = ยัง (ฝั่งล่าสุด)
double     g_t5_cur_z       = 0.0;     // Z สุดขั้วในทิศที่แตะ
int        g_t5_pend_dir    = 0;       // รอเปิดในแท่งนี้ (จากแท่งก่อน)
double     g_t5_pend_z      = 0.0;
datetime   g_t5_pend_until  = 0;       // ติดตัวกรอง → ลองใหม่ได้ถึงเวลานี้
datetime   g_t5_next_try    = 0;
// --- ชุด S2 (EA จริง) ---
S2State    g_s2;
datetime   g_s2_next_try    = 0;
SpeedTracker g_trk_live;               // สถิติ tick ของแท่งปัจจุบัน (tick สด)
SpeedTracker g_trk_rp;                 // สถิติ tick ของแท่งที่ Tick Replay กำลังเล่น
BarSpeed   g_spd_hist[];               // สถิติ tick ของแท่งที่ผ่านมา (สด + Tick Replay) เรียงตามเวลาแท่ง
int        g_lbl_ver        = 0;       // ป้ายบนแท่งเปลี่ยน → จัดตำแหน่งใหม่
datetime   g_pn_bar         = 0;       // แท่งที่กล่องรายละเอียดแสดงอยู่ (0 = แท่งปัจจุบัน)
int        g_pn_side        = -1;      // ฝั่งที่เมาส์ชี้ (−1 = เลือกฝั่งที่ Z สูงกว่า)
string     g_pn_text        = "";
bool       g_en[8];                    // ปุ่มบนกราฟ: index 2-4 = ระดับ T2-T4, 5 = ชุด T5, 6 = ชุด S2, 7 = 1 ชุด/แท่ง
datetime   g_set_bar        = 0;       // แท่งที่วางชุด T2-T4 ล่าสุด (EA จริง)
string     g_lay_sig        = "";      // สถานะกราฟตอนจัดป้ายไม้ล่าสุด
bool       g_bar_changed    = false;   // ขึ้นแท่งใหม่ (TF ของ Z) → ล้างการเฝ้า
long       g_last_tick_msc  = 0;
datetime   g_next_try       = 0;
string     g_last_status    = "เริ่มทำงาน";
datetime   g_del_retry      = 0;       // ลบออเดอร์รอไม่สำเร็จ → ลองใหม่หลังเวลานี้
uint       g_heavy_ms       = 0;       // งานแสดงผลหนักรอบล่าสุด (GetTickCount)

uint       g_tick_local     = 0;       // GetTickCount ตอน tick ล่าสุด (นาฬิกาเสริม)

// สถานะต่อไม้จริง (เกราะกำไร) — สร้างเมื่อเห็นไม้ครั้งแรก, ลบเมื่อไม้ปิด
struct PosMon {
   ulong  tk;
   long   open_msc;       // เวลาเข้า (POSITION_TIME_MSC)
   double mfe;            // กำไรสูงสุด (ราคา)
   long   mfe_msc;
   int    lock_lv;        // ขั้นเกราะที่ขยับ SL แล้ว (0 = ยัง, 4 = ไล่จี้โหมดวิ่งยาว)
   long   lock_on;        // เวลาที่เกราะขยับ SL ครั้งแรก (0 = ยัง)
   long   next_try;       // สั่งปิด / แก้ไม่สำเร็จ → ลองใหม่หลังเวลานี้ (msc)
   int    sys;            // ชุด: 1 = T2-T4 / 2 = T5 / 3 = S2
   int    mode;           // 0 = ปกติ / 1 = วิ่งยาว
   bool   both;           // T2-T4: ชุดนี้ถูกเกี่ยวทั้ง 2 ขา (ขานี้คือขาที่ 2)
   double want_sl;        // SL ที่ต้องตั้ง (ราคา Stop ของขาแรก, 0 = ไม่มี)
   long   last_mod;       // ขยับ SL ล่าสุด (msc)
};
ulong      g_both_tk        = 0;       // ขาที่ 2 ของชุดที่ถูกเกี่ยวทั้ง 2 ขา (รอตั้ง SL)
double     g_both_sl        = 0.0;
PosMon     g_pm[];

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
   bool new_bar    = (t0 != g_zbar_time);
   if(g_zbar_time != 0 && new_bar) {
      g_bar_changed = true;
      // T5: แท่งที่เพิ่งปิดแตะ > T5 → รอเปิดในแท่งนี้
      g_t5_pend_dir   = g_t5_cur_dir;
      g_t5_pend_z     = g_t5_cur_z;
      g_t5_pend_until = t0 + (datetime)InpT5_RetrySec;
      g_t5_cur_dir    = 0;
      g_t5_cur_z      = 0.0;
      if(g_t5_pend_dir != 0 && g_en[5])
         PrintFormat("🔔 T5: แท่งก่อนแตะ Z %+.2f → เปิด %s สวนตอนแท่งใหม่", g_t5_pend_z, (g_t5_pend_dir == -1 ? "SELL" : "BUY"));
   }

   // ช่วงแกว่งของแท่งปัจจุบัน
   g_bar0_hi = iHigh(_Symbol, InpZ_Timeframe, 0);
   g_bar0_lo = iLow (_Symbol, InpZ_Timeframe, 0);
   g_bar0_open = iOpen(_Symbol, InpZ_Timeframe, 0);
   g_bar0_fz   = FloatAtOpen(g_zc, g_bar0_open, g_bar0_fsma, g_bar0_fsd);

   if(new_bar) {   // S2: บริบทของแท่งปิดล่าสุด
      MqlRates pr;
      pr.time  = iTime(_Symbol, InpZ_Timeframe, 1);
      pr.open  = iOpen(_Symbol, InpZ_Timeframe, 1);
      pr.high  = iHigh(_Symbol, InpZ_Timeframe, 1);
      pr.low   = iLow (_Symbol, InpZ_Timeframe, 1);
      pr.close = c[n - 1];
      S2NewBar(g_s2, t0, c, pr, g_bar0_hi, g_bar0_lo);
      S2RestoreDone();
      SetBarRestore(t0);
   }

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

// ระดับวิกฤตของชุด T2-T4 (ตรวจ T4 → T3 → T2, ข้ามระดับที่ปิดด้วยปุ่ม), zf = Z_float ในทิศของฝั่งนี้:
//   4 = Z ตัวใดตัวหนึ่ง > T4 | 3 = > T3 (T3 / T4 ไม่ต้องลอย)
//   2 = ต้องลอย zf > InpFloatMin แล้ว Z ตัวใดตัวหนึ่ง > T2 (v14.80) | 0 = ไม่ถึง   (T5 เป็นชุดแยก ไม่อยู่ในนี้)
int TierOf(int dir, double zr, double zs, double zf) {
   double hi = MathMax((dir == -1) ? zr : -zr, (dir == -1) ? zs : -zs);
   if(g_en[4] && hi > InpT4_Z) return 4;
   if(g_en[3] && hi > InpT3_Z) return 3;
   if(!g_en[2] || (InpFloatFilter && zf <= InpFloatMin)) return 0;
   if(hi > InpT2_Z) return 2;
   return 0;
}

// เวลารอ (ไม่มีค่าสุดขั้วใหม่) ของแต่ละระดับ
long TierWaitMs(int tier) {
   if(tier >= 4) return (long)InpT4_Sec * 1000;
   return (long)(tier == 3 ? InpT3_Sec : InpT2_Sec) * 1000;
}

// Lot ตามระดับที่ยิง: T2 = InpLot + step, T3 = +2·step, T4 = +3·step, T5 = +4·step
double TierLot(int tier) { return NormalizeLot(InpLot + (MathMax(1, tier) - 1) * InpTierLotStep); }

string StageTag(int tier) { return "T" + IntegerToString(tier); }

void WatchReset(WatchState &w) {
   w.active   = false;
   w.tier     = 0;
   w.max_tier = 0;
   w.ext_r    = 0.0;
   w.ext_s    = 0.0;
   w.ext_px   = 0.0;
   w.last_new = 0;
   w.started  = 0;
   w.start_px = 0.0;
}

// อัปเดตการเฝ้า: เริ่มเมื่อเข้าเงื่อนไขระดับใดระดับหนึ่ง, ระดับ = ลึกสุดที่ไปถึง (Z หลุดเกณฑ์ระหว่างจับเวลาได้ ไม่ลดระดับ)
//   นับเวลาใหม่เมื่อ Bid ทำยอดใหม่ (SELL = สูงขึ้น / BUY = ต่ำลง) เกินจุดอ้างอิงล่าสุด ≥ InpNoNewExt_Pts แล้วย้ายจุดอ้างอิง (v14.80)
//   การเฝ้าระดับ T2: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่งกลับถึง 0 → ยกเลิกแล้วรอสัญญาณใหม่
//   zf = Z_float ในทิศของฝั่งนี้ — ยกเลิกจากภายนอก: ขึ้นแท่งใหม่ / ชุด T2-T4 ยังไม่จบ
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
      w.ext_px   = bid;
      w.last_new = now_msc;
      w.started  = now_msc;
      w.start_px = bid;
      return;
   }
   if(dir == -1) { if(zr > w.ext_r) w.ext_r = zr; if(zs > w.ext_s) w.ext_s = zs; }
   else          { if(zr < w.ext_r) w.ext_r = zr; if(zs < w.ext_s) w.ext_s = zs; }
   double eps = PtsToPrice(InpNoNewExt_Pts);
   if(dir == -1 ? (bid >= w.ext_px + eps) : (bid <= w.ext_px - eps)) { w.ext_px = bid; w.last_new = now_msc; }
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
#define SLM_TREND     2   // ตาม: ราคาเข้า ± InpTrendSL_Pts (v14.80)
#define SLM_FIXED     4   // T5: ราคาเข้า ± InpT5_SL_Pts
#define SLM_S2        5   // S2: High / Low แท่งปัจจุบัน ± สเปรด (v14.90)

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

// SL ฝั่งตาม (dir = ทิศของไม้): คงที่ InpTrendSL_Pts จากราคาเข้า (v14.80)
double TrendSL(int dir, double entry, int &mode) {
   mode = SLM_TREND;
   return entry - dir * PtsToPrice(InpTrendSL_Pts);
}

string SLModeCode(int m) {
   switch(m) {
      case SLM_PEAK_CAP:  return "PEAK_CAP";
      case SLM_TREND:     return "TREND_FIXED";
      case SLM_FIXED:     return "FIXED";
      case SLM_S2:        return "S2_BAR_EXT";
   }
   return "PEAK";
}

string SLModeText(int m) {
   switch(m) {
      case SLM_PEAK_CAP:  return StringFormat("เพดาน %.0f จุดจากราคาเข้า (ยอดแท่ง ± %.0f ห่างเกิน)", InpCounterMaxSL_Pts, InpSLPeak_Pts);
      case SLM_TREND:     return StringFormat("คงที่ %.0f จุดจากราคาเข้า (ตามน้ำ)", InpTrendSL_Pts);
      case SLM_FIXED:     return StringFormat("คงที่ %.0f จุดจากราคาเข้า (T5)", InpT5_SL_Pts);
      case SLM_S2:        return StringFormat("ยอดแท่งปัจจุบัน ± สเปรด (S2, ต่ำสุด %.0f, TP %.1f เท่า)", InpS2_MinSL_Pts, InpS2_RR);
   }
   return StringFormat("ยอดแท่ง ± %.0f", InpSLPeak_Pts);
}

//--------------------------------------------------------------------
// 📋 ชุด S2 สวนที่ไส้แท่งปิดล่าสุด (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//--------------------------------------------------------------------
void S2Clear(S2State &s) {
   s.bar = 0; s.ok = false;
   s.p_open = 0.0; s.p_high = 0.0; s.p_low = 0.0; s.p_close = 0.0; s.p_zhi = 0.0; s.p_zlo = 0.0;
   s.hi = 0.0; s.lo = 0.0; s.done = false;
   for(int k = 0; k < 2; k++) { s.sb[k] = false; s.cancel[k] = false; s.last_new[k] = 0; }
}

// แท่งใหม่: c[0..n-1] = ราคาปิด n แท่งที่ปิดแล้ว (c[n-1] = แท่งปิดล่าสุด), prev = OHLC แท่งปิดล่าสุด, hi / lo = แท่งปัจจุบันถึงตอนนี้
void S2NewBar(S2State &s, datetime bar, const double &c[], const MqlRates &prev, double hi, double lo) {
   S2Clear(s);
   s.bar = bar;
   s.p_open = prev.open; s.p_high = prev.high; s.p_low = prev.low; s.p_close = prev.close;
   s.hi = hi; s.lo = lo;
   int    n = InpZ_Period;
   double zr, zs;
   s.ok    = (prev.high > 0.0 && prev.low > 0.0 && ArraySize(c) >= n);
   s.p_zhi = (s.ok && ZForBarPrice(c, n - 1, prev.high, zr, zs)) ? MathMax(zr, zs) : 0.0;
   s.p_zlo = (s.ok && ZForBarPrice(c, n - 1, prev.low,  zr, zs)) ? MathMin(zr, zs) : 0.0;
}

// ฝั่ง k (0 = ไส้บน → SELL / 1 = ไส้ล่าง → BUY): แท่งปิดล่าสุดถึงเกณฑ์ไหม
bool S2Armed(const S2State &s, int k) { return s.ok && ((k == 0) ? (s.p_zhi > InpS2_PrevZ) : (s.p_zlo < -InpS2_PrevZ)); }

// tick ของแท่งปัจจุบัน: High / Low → ยกเลิก (ทะลุยอดแท่งปิดล่าสุด) / สแตนบาย (เข้าไส้) / ยอดใหม่ระหว่างสแตนบาย
void S2Tick(S2State &s, double bid, long msc) {
   if(s.bar == 0) return;
   bool nh = (s.hi <= 0.0 || bid > s.hi), nl = (s.lo <= 0.0 || bid < s.lo);
   if(nh) s.hi = bid;
   if(nl) s.lo = bid;
   for(int k = 0; k < 2; k++) {
      if(!S2Armed(s, k) || s.cancel[k]) continue;
      bool brk = (k == 0) ? (s.hi > s.p_high) : (s.lo < s.p_low);
      if(brk) { s.cancel[k] = true; s.sb[k] = false; continue; }
      if(!s.sb[k]) {
         bool in_zone = (k == 0) ? (bid >= MathMax(s.p_open, s.p_close)) : (bid <= MathMin(s.p_open, s.p_close));
         if(in_zone) { s.sb[k] = true; s.last_new[k] = msc; }
         continue;
      }
      if((k == 0) ? nh : nl) s.last_new[k] = msc;
   }
}

long S2Deadline(const S2State &s, int k) { return s.last_new[k] + (long)InpS2_NoNewSec * 1000; }

// พร้อมยิงไหม → −1 SELL / +1 BUY / 0
int S2Ready(const S2State &s, long msc) {
   if(s.sb[0] && !s.cancel[0] && s.hi < s.p_high && msc >= S2Deadline(s, 0)) return -1;
   if(s.sb[1] && !s.cancel[1] && s.lo > s.p_low  && msc >= S2Deadline(s, 1)) return  1;
   return 0;
}


// ชุด T5: บันทึกการแตะ > InpT5_Z ในแท่ง (แตะทั้ง 2 ฝั่ง = ใช้ฝั่งล่าสุด) — dir = ทิศของไม้สวน
void T5Touch(int &cur_dir, double &cur_z, double zr, double zs) {
   double hi = MathMax(zr, zs), lo = MathMin(zr, zs);
   if(hi > InpT5_Z)  { if(cur_dir != -1) { cur_dir = -1; cur_z = hi; } else cur_z = MathMax(cur_z, hi); }
   if(lo < -InpT5_Z) { if(cur_dir !=  1) { cur_dir =  1; cur_z = lo; } else cur_z = MathMin(cur_z, lo); }
}

// S2: SL = High (SELL) / Low (BUY) แท่งปัจจุบัน ± สเปรด, ระยะต่ำสุด InpS2_MinSL_Pts, TP = InpS2_RR × ระยะ SL (v14.90)
//   คืน false = ระยะ SL เกิน InpS2_MaxSL_Pts → ยกเลิก
bool S2Plan(const S2State &s, int dir, double bid, double ask, double &sl, double &tp, double &dist) {
   double entry = (dir == -1) ? bid : ask, spread = ask - bid;
   double raw   = (dir == -1) ? s.hi + spread : s.lo - spread;
   dist = MathMax((dir == -1) ? raw - entry : entry - raw, PtsToPrice(InpS2_MinSL_Pts));
   sl   = entry - dir * dist;
   tp   = entry + dir * dist * InpS2_RR;
   return (InpS2_MaxSL_Pts <= 0.0 || dist <= PtsToPrice(InpS2_MaxSL_Pts) + _Point * 0.5);
}

// SL a ดีกว่า (ฝั่งกำไรมากกว่า) b ไหม — b ≤ 0 = ยังไม่มี SL
bool SLBetter(int dir, double a, double b) { return (b <= 0.0) || ((dir == 1) ? (a > b + _Point * 0.5) : (a < b - _Point * 0.5)); }

// เกราะ / ไล่จี้ (ใช้ร่วมกัน) → SL เป้าหมาย (0 = ยังไม่ขยับ) + lv (1-3 = เกราะขั้น, 4 = ไล่จี้)
//   mode 0 = เกราะ 3 ขั้น / 1 = วิ่งยาว: เกราะขั้น 1 + ไล่จี้ห่าง InpLongTrail_Pts เมื่อกำไรสูงสุดถึง InpLongTrailStart_Pts
double ShieldSL(int dir, double entry, double mfe, double bid, double ask, int mode, int &lv) {
   double lock;
   if(mode == 0) { lv = LockOf(mfe, lock); return (lv > 0) ? entry + dir * lock : 0.0; }
   lv = 0;
   double sl = 0.0;
   if(InpLock1_Trig_Pts > 0.0 && mfe >= PtsToPrice(InpLock1_Trig_Pts)) { sl = entry + dir * PtsToPrice(InpLock1_Pts); lv = 1; }
   if(InpLongTrailStart_Pts > 0.0 && mfe >= PtsToPrice(InpLongTrailStart_Pts)) {
      double t = (dir == 1) ? bid - PtsToPrice(InpLongTrail_Pts) : ask + PtsToPrice(InpLongTrail_Pts);
      if(sl == 0.0 || SLBetter(dir, t, sl)) { sl = t; lv = 4; }
   }
   return sl;
}

// เข้าโหมดวิ่งยาวได้ไหม: T5 / T2-T4 ที่เกี่ยวฝั่งเดียว (ไม่ใช่ขาที่ 2 ของชุดที่เกี่ยวทั้งคู่) + กำไรสูงสุดถึงเกราะขั้น 1
bool LongModeDue(int sys, bool both, double mfe) {
   return (sys == 1 || sys == 2) && !both && InpLock1_Trig_Pts > 0.0 && mfe >= PtsToPrice(InpLock1_Trig_Pts);
}

// เกราะกำไร 3 ขั้น (ใช้ร่วมกัน): ขั้นสูงสุดที่กำไรสูงสุด mfe ถึง → lv (0 = ยังไม่ถึง) + ระยะล็อกจากราคาเข้า (ราคา)
int LockOf(double mfe, double &lock) {
   lock = 0.0;
   if(InpLock3_Trig_Pts > 0.0 && mfe >= PtsToPrice(InpLock3_Trig_Pts)) { lock = PtsToPrice(InpLock3_Pts); return 3; }
   if(InpLock2_Trig_Pts > 0.0 && mfe >= PtsToPrice(InpLock2_Trig_Pts)) { lock = PtsToPrice(InpLock2_Pts); return 2; }
   if(InpLock1_Trig_Pts > 0.0 && mfe >= PtsToPrice(InpLock1_Trig_Pts)) { lock = PtsToPrice(InpLock1_Pts); return 1; }
   return 0;
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

// S2: Market (dir = ทิศของไม้) พร้อม SL / TP ที่โบรก (เคารพ Stops Level) — คอมเมนต์ "<InpOrderComment> S2 X2.80"
bool OpenMarketS2(int dir, double bid, double ask, double sl, double tp, double z_ref) {
   double lot   = NormalizeLot(InpS2_Lot);
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dir == -1) { sl = MathMax(sl, ask + stops + _Point); tp = MathMin(tp, bid - stops - _Point); }
   else          { sl = MathMin(sl, bid - stops - _Point); tp = MathMax(tp, ask + stops + _Point); }
   sl = ND(sl); tp = ND(tp);
   string cmt = StringFormat("%s S2 X%.2f", InpOrderComment, MathAbs(z_ref));
   bool   ok  = (dir == -1) ? trade.Sell(lot, _Symbol, bid, sl, tp, cmt) : trade.Buy(lot, _Symbol, ask, sl, tp, cmt);
   uint   rc  = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      double px = trade.ResultPrice();
      PrintFormat("✅ เปิด S2 สวนที่ไส้ %s %.2f lot @ %s | SL %s (ห่าง %.0f) | TP %s (ห่าง %.0f) | Z ที่ยอดแท่งก่อน %+.2f",
                  (dir == -1 ? "SELL" : "BUY"), lot, DoubleToString(px, _Digits), DoubleToString(sl, _Digits), PriceToPts(MathAbs(sl - px)),
                  DoubleToString(tp, _Digits), PriceToPts(MathAbs(tp - px)), z_ref);
      return true;
   }
   PrintFormat("❌ เปิด S2 %s ไม่สำเร็จ: %u %s", (dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
   return false;
}

// T5: สวนกลับด้วย Market (dir = ทิศของไม้), SL คงที่ InpT5_SL_Pts จากราคาเข้า (เคารพ Stops Level), ไม่มี TP (ตัดจบตามเวลา)
//   คอมเมนต์ "<InpOrderComment> T5 M X4.25"
bool OpenMarketT5(int dir, double bid, double ask, double ext_z) {
   double lot   = TierLot(5);
   double price = (dir == -1) ? bid : ask;
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double dist  = PtsToPrice(InpT5_SL_Pts);
   double sl    = (dir == -1) ? MathMax(price + dist, ask + stops + _Point) : MathMin(price - dist, bid - stops - _Point);
   sl = ND(sl);
   string cmt = StringFormat("%s %s M X%.2f", InpOrderComment, StageTag(5), ext_z);
   bool   ok  = (dir == -1) ? trade.Sell(lot, _Symbol, bid, sl, 0.0, cmt) : trade.Buy(lot, _Symbol, ask, sl, 0.0, cmt);
   uint   rc  = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      PrintFormat("✅ เปิด T5 สวน %s %.2f lot @ %s | SL %s (คงที่ %.0f จุด) | Z สุดขั้ว %.2f",
                  (dir == -1 ? "SELL" : "BUY"), lot, DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(sl, _Digits), InpT5_SL_Pts, ext_z);
      return true;
   }
   PrintFormat("❌ เปิด T5 %s ไม่สำเร็จ: %u %s", (dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
   return false;
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

// ชุดของไม้จากคอมเมนต์: 1 = T2-T4 (Stop) / 2 = T5 (Market) / 3 = S2
int SysOfComment(string c) {
   if(StringFind(c, InpOrderComment + " S2") >= 0) return 3;
   if(StringFind(c, " T5 ") >= 0) return 2;
   return 1;
}

// จำนวนไม้ที่ถืออยู่ของชุด sys
int SysPositions(int sys) {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t != 0 && IsOurPosition() && SysOfComment(PositionGetString(POSITION_COMMENT)) == sys) n++;
   }
   return n;
}

// ชุด T2-T4 ยังไม่จบ = ยังมีออเดอร์รอ (มีแต่ของชุดนี้) หรือไม้ของชุดนี้ถืออยู่ (รู้สถานะได้แม้ EA รีสตาร์ท) — T5 / S2 ไม่นับ
bool SetActive() { return OurPendingTotal() > 0 || SysPositions(1) > 0; }

// ระดับ (T2-T5) จากคอมเมนต์ของดีลเปิด เช่น "7L-CNT T3 C X3.25" (0 = อ่านไม่ได้ / S2) — ใช้กับมาร์กจุดเปิดไม้
int TierFromComment(string c) {
   for(int t = 5; t >= 2; t--)
      if(StringFind(c, " T" + IntegerToString(t) + " ") >= 0) return t;
   return 0;
}

// ฝั่งของออเดอร์จากคอมเมนต์: "ตาม" (F) / "S2" / "สวน" (C, M = T5 Market)
string KindFromComment(string c) {
   if(StringFind(c, " F ") >= 0) return "ตาม";
   if(SysOfComment(c) == 3) return "S2";
   return "สวน";
}


//--------------------------------------------------------------------
// 🎯 วางชุดออเดอร์ (EA จริง)
//--------------------------------------------------------------------
// ครบเวลาเฝ้าของระดับ (T2 5 วิ / T3 2 วิ / T4 2 วิ) → ตัวกรอง → วาง Stop สวน + Stop ตาม (ติดตัวกรอง = ทิ้งสัญญาณ)
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
   datetime expire = now + (datetime)(InpStopExpire_Min * 60);
   double   pc = 0.0, pf = 0.0;
   double   dist   = PtsToPrice(InpStopDist_Pts);
   double   ec     = (dir == 1) ? ask + dist : bid - dist;   // ราคาเข้าของขาสวน / ขาตาม
   double   ef     = (dir == 1) ? bid - dist : ask + dist;
   int      mc, mf;
   double   slc    = CounterSL(dir, ec, hi, lo, mc);
   double   slf    = TrendSL(-dir, ef, mf);
   bool     okc = PlaceStop( dir, tier, "C", bid, ask, slc, SLModeText(mc), expire, ext_z, pc);
   bool     okf = PlaceStop(-dir, tier, "F", bid, ask, slf, SLModeText(mf), expire, ext_z, pf);
   if(okc || okf) {
      g_set_bar     = g_zbar_time;
      g_last_status = StringFormat("วางชุด %s %s (Lot %.2f) | สวน %s @ %s%s | ตาม %s @ %s%s | สุดขั้ว R %+.2f / S %+.2f",
                                   side, StageTag(tier), TierLot(tier),
                                   (dir == -1 ? "SELL STOP" : "BUY STOP"), DoubleToString(pc, _Digits), (okc ? "" : " ❌"),
                                   (dir == -1 ? "BUY STOP" : "SELL STOP"), DoubleToString(pf, _Digits), (okf ? "" : " ❌"),
                                   w.ext_r, w.ext_s);
      PrintFormat("   📈 สถิติแท่ง ณ ตอนสัญญาณ (ฝั่งกระชาก): %s", LiveStatText(dir == -1 ? 0 : 1));
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
   } else {
      g_next_try    = now + 1;   // กันยิงคำสั่งรัว ๆ เมื่อโบรกปฏิเสธ (ยังเฝ้าต่อ)
      g_last_status = side + " วางชุดออเดอร์ไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

// เรียกทุก Tick และทุก 200 ms — ขึ้นแท่งใหม่ = ล้างการเฝ้า, ชุด T2-T4 ยังไม่จบ (ออเดอร์รอ / ไม้ของชุดนี้) = ไม่หาสัญญาณใหม่ (T5 / S2 ไม่นับ)
//   (เวลาตลาด / สเปรด ตรวจตอนวางใน LiveFire)
void LiveSignalStep(long now_msc, int ts, double bid, double ask, bool update_watch) {
   if(!g_z_valid) return;
   if(g_bar_changed || SetActive()) {
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
      g_bar_changed = false;
      if(SetActive()) return;
   }
   if(SetBarUsed(g_set_bar, g_zbar_time)) { WatchReset(g_wsell); WatchReset(g_wbuy); return; }   // 1 ชุด/แท่ง
   if(update_watch) {
      WatchUpdate(g_wsell, -1, g_z_reg, g_z_sma, now_msc, bid, ask, ZFloat(-1, g_bar0_fz));
      WatchUpdate(g_wbuy,   1, g_z_reg, g_z_sma, now_msc, bid, ask, ZFloat( 1, g_bar0_fz));
   }
   if(WatchReady(g_wsell, now_msc))     LiveFire(-1, ts, bid, ask);
   else if(WatchReady(g_wbuy, now_msc)) LiveFire( 1, ts, bid, ask);
}

// ชุด T5 (EA จริง): แท่งก่อนแตะ > T5 → เปิด Market สวนตอนแท่งใหม่ — ไม่ต่อคิวชุดอื่น, ถือได้ทีละ 1 ไม้
//   ติดตัวกรอง → ลองใหม่ได้ภายใน InpT5_RetrySec วินาทีแรกของแท่ง แล้วทิ้ง
void LiveT5Step(datetime now, int ts, double bid, double ask) {
   if(g_t5_pend_dir == 0) return;
   int    dir  = g_t5_pend_dir;
   string side = (dir == -1) ? "SELL" : "BUY";
   if(!g_en[5]) { g_t5_pend_dir = 0; return; }
   if(SysPositions(2) > 0) { g_t5_pend_dir = 0; g_last_status = "T5 " + side + ": ยังถือไม้ T5 อยู่ → ไม่เปิดซ้อน"; return; }
   if(now > g_t5_pend_until) {
      g_t5_pend_dir = 0;
      g_last_status = StringFormat("T5 %s: ติดตัวกรองเกิน %d วิแรกของแท่ง → ทิ้งสัญญาณ", side, InpT5_RetrySec);
      return;
   }
   string why = EntryBlockReason(ts, bid, ask);
   if(why == "" && !TradeAllowed()) why = "ปิด Algo Trading อยู่";
   if(why != "") { g_last_status = "T5 " + side + " รอ (แท่งก่อนแตะ Z " + DoubleToString(g_t5_pend_z, 2) + "): " + why; return; }
   if(now < g_t5_next_try) return;
   if(OpenMarketT5(dir, bid, ask, MathAbs(g_t5_pend_z))) {
      g_last_status = StringFormat("เปิด T5 สวน %s ตอนแท่งใหม่ (Lot %.2f, SL คงที่ %.0f) | แท่งก่อนแตะ Z %+.2f", side, TierLot(5), InpT5_SL_Pts, g_t5_pend_z);
      g_t5_pend_dir = 0;
   } else {
      g_t5_next_try = now + 1;
      g_last_status = "T5 " + side + " ส่งคำสั่งไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

// ชุด S2 (EA จริง): ครั้งเดียวต่อแท่ง, ถือได้ทีละ 1 ไม้ — ครบเวลาแล้วติดตัวกรอง = ทิ้งสัญญาณของแท่งนี้
void LiveS2Step(datetime now, int ts, double bid, double ask, long msc) {
   if(!g_en[6] || g_s2.done || !g_s2.ok || now < g_s2_next_try) return;
   int d = S2Ready(g_s2, msc);
   if(d == 0 || SysPositions(3) > 0) return;
   string why = EntryBlockReason(ts, bid, ask);
   if(why == "" && !TradeAllowed()) why = "ปิด Algo Trading อยู่";
   if(why != "") { g_s2.done = true; g_last_status = "S2 ครบเวลาแต่ติด: " + why + " → ทิ้งสัญญาณของแท่งนี้"; return; }
   double zref = (d == -1) ? g_s2.p_zhi : g_s2.p_zlo;
   double sl, tp, dist;
   if(!S2Plan(g_s2, d, bid, ask, sl, tp, dist)) {
      g_s2.done     = true;
      g_last_status = StringFormat("S2 %s: ระยะ SL %.0f > %.0f จุด → ยกเลิกสัญญาณของแท่งนี้", (d == -1 ? "SELL" : "BUY"), PriceToPts(dist), InpS2_MaxSL_Pts);
      Print(g_last_status);
      return;
   }
   if(OpenMarketS2(d, bid, ask, sl, tp, zref)) {
      g_s2.done     = true;
      g_last_status = StringFormat("เปิด S2 สวนที่ไส้ %s (Lot %.2f) | Z ที่ยอดแท่งก่อน %+.2f", (d == -1 ? "SELL" : "BUY"), NormalizeLot(InpS2_Lot), zref);
   } else {
      g_s2_next_try = now + 1;
      g_last_status = "S2 ส่งคำสั่งไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

// S2 เปิดไปแล้วในแท่งนี้ไหม (เริ่ม EA / ขึ้นแท่งใหม่)
void S2RestoreDone() {
   if(g_s2.bar == 0 || !HistorySelect(g_s2.bar, ServerNow() + 60)) return;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || !IsOurDeal(d, DEAL_ENTRY_IN)) continue;
      if(SysOfComment(HistoryDealGetString(d, DEAL_COMMENT)) == 3 && (datetime)HistoryDealGetInteger(d, DEAL_TIME) >= g_s2.bar) { g_s2.done = true; break; }
   }
}

// แท่งนี้วางชุด T2-T4 ไปแล้วไหม (เริ่ม EA / ขึ้นแท่งใหม่): ออเดอร์ Stop ของ EA (รอ / ประวัติ) ที่วางตั้งแต่เปิดแท่ง
void SetBarRestore(datetime bar) {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(t != 0 && IsOurOrder() && (datetime)OrderGetInteger(ORDER_TIME_SETUP) >= bar) { g_set_bar = bar; return; }
   }
   if(!HistorySelect(bar, ServerNow() + 60)) return;
   for(int i = HistoryOrdersTotal() - 1; i >= 0; i--) {
      ulong o = HistoryOrderGetTicket(i);
      if(o == 0 || HistoryOrderGetInteger(o, ORDER_MAGIC) != InpMagic || HistoryOrderGetString(o, ORDER_SYMBOL) != _Symbol) continue;
      long ty = HistoryOrderGetInteger(o, ORDER_TYPE);
      if((ty == ORDER_TYPE_BUY_STOP || ty == ORDER_TYPE_SELL_STOP) && (datetime)HistoryOrderGetInteger(o, ORDER_TIME_SETUP) >= bar) { g_set_bar = bar; return; }
   }
}

// 1 ชุด/แท่ง: แท่งนี้วางชุด T2-T4 ไปแล้ว → ไม่เฝ้า / วางเพิ่ม
bool SetBarUsed(datetime set_bar, datetime bar) { return g_en[7] && bar > 0 && set_bar == bar; }

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

int PosMonGet(ulong tk, long open_msc, long now_msc, double prof, int sys, double sl_prof, bool is_trend, ulong pos_id) {
   for(int i = ArraySize(g_pm) - 1; i >= 0; i--) if(g_pm[i].tk == tk) return i;
   int n = ArraySize(g_pm);
   ArrayResize(g_pm, n + 1);
   g_pm[n].tk       = tk;
   g_pm[n].open_msc = open_msc;
   g_pm[n].mfe      = MathMax(0.0, prof);
   g_pm[n].mfe_msc  = now_msc;
   g_pm[n].lock_lv  = 0;
   g_pm[n].lock_on  = 0;
   g_pm[n].next_try = 0;
   g_pm[n].sys      = sys;
   g_pm[n].both     = (sys == 1) && SetOtherFilled(pos_id, is_trend);   // รีสตาร์ท: อ่านจากประวัติ
   g_pm[n].want_sl  = 0.0;
   g_pm[n].last_mod = 0;
   // รีสตาร์ท: SL อยู่ฝั่งกำไรถึงเกราะขั้น 1 แล้ว = อยู่ในโหมดวิ่งยาว
   g_pm[n].mode     = (sys != 3 && !g_pm[n].both && InpLock1_Trig_Pts > 0.0 && sl_prof >= PtsToPrice(InpLock1_Pts) - _Point) ? 1 : 0;
   return n;
}

// ราคาของออเดอร์ที่เปิดไม้ (ราคา Stop) จากประวัติ — ทนการรีสตาร์ท (0 = อ่านไม่ได้)
double OrderPriceOfPosition(ulong pos_id) {
   if(!HistoryOrderSelect(pos_id)) return 0.0;
   return HistoryOrderGetDouble(pos_id, ORDER_PRICE_OPEN);
}

// ขาชุด T2-T4 นี้ อีกฝั่งเคยถูกเกี่ยวไหม: หาดีลเปิดของ EA ชนิดตรงข้าม ที่ออเดอร์วางพร้อมกัน (±5 วิ)
bool SetOtherFilled(ulong pos_id, bool is_trend) {
   if(!HistoryOrderSelect(pos_id)) return false;
   long setup = HistoryOrderGetInteger(pos_id, ORDER_TIME_SETUP);
   if(!HistorySelect((datetime)(setup - 10), ServerNow() + 60)) return false;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || !IsOurDeal(d, DEAL_ENTRY_IN)) continue;
      string c = HistoryDealGetString(d, DEAL_COMMENT);
      if(SysOfComment(c) != 1 || ((StringFind(c, " F ") >= 0) == is_trend)) continue;
      ulong o = (ulong)HistoryDealGetInteger(d, DEAL_ORDER);
      if(o == pos_id || !HistoryOrderSelect(o)) continue;
      if(MathAbs(HistoryOrderGetInteger(o, ORDER_TIME_SETUP) - setup) <= 5) return true;
   }
   return false;
}

void PosMonPrune() {
   int n = ArraySize(g_pm), w = 0;
   for(int i = 0; i < n; i++) if(PositionSelectByTicket(g_pm[i].tk)) g_pm[w++] = g_pm[i];
   if(w != n) ArrayResize(g_pm, w);
}

// ช่วงร้อน = กำลังเฝ้าสัญญาณ → ข้ามงานแสดงผลหนัก ให้ส่งคำสั่งได้ทันที

// เวลาตอนนี้ (msc, นาฬิกาเซิร์ฟเวอร์): เวลา tick ล่าสุด + เวลาที่ผ่านไปตามนาฬิกาในเครื่อง — แม่นแม้ tick ห่าง
long NowMsc() {
   long srv = (long)ServerNow() * 1000;
   if(g_last_tick_msc <= 0) return srv;
   return MathMax(g_last_tick_msc + (long)(GetTickCount() - g_tick_local), srv);
}
bool LiveHot() {
   return (g_wsell.active || g_wbuy.active || g_s2.sb[0] || g_s2.sb[1] || g_t5_pend_dir != 0);
}

// เวลาตัดจบของไม้ที่เปิดเวลา opened: ปิดแท่งที่ InpExitBars หลังแท่งที่ถูกเกี่ยว (= เวลาเปิดของแท่งถัดไป)
datetime ExitTimeOf(datetime opened) { return ExitTimeOfN(opened, InpExitBars); }

// เวลาตัดจบเมื่อถือ bars แท่งหลังแท่งที่ถูกเกี่ยว (โหมดวิ่งยาวใช้ InpLongExitBars)
datetime ExitTimeOfN(datetime opened, int bars) {
   return BarStartOf(opened) + (datetime)((long)(bars + 1) * PeriodSeconds(InpZ_Timeframe));
}

// เรียกทุก Tick และทุก 200 ms:
//   1) ออเดอร์รอ: ครบ InpStopExpire_Min นาที / เข้าช่วงห้ามเข้าก่อนปิดสัปดาห์ → ยกเลิก
//   2) ไม้ที่ถือ: ตัดจบตามเวลา → เกราะกำไร 3 ขั้น (5,000 → +1,500 / 10,000 → +5,000 / 20,000 → +10,000)
void ManageOrders(datetime now, int ts, long now_msc) {
   // 1) ออเดอร์รอ: ครบอายุ / ช่วงห้ามเข้าก่อนปิดสัปดาห์ → ยกเลิก
   if(now >= g_del_retry) {
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0 || !IsOurOrder()) continue;
         datetime setup   = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         bool     expired = (now >= setup + (datetime)(InpStopExpire_Min * 60));
         if(!expired && ts != TS_WAIT_CLOSE && ts != TS_CLOSING) continue;
         if(trade.OrderDelete(ticket))
            PrintFormat("🗑️ ยกเลิกออเดอร์รอ #%I64u (%s)", ticket, (expired ? StringFormat("ครบ %d นาทียังไม่ถูกเกี่ยว", InpStopExpire_Min) : "ช่วงห้ามเข้าก่อนปิดสัปดาห์"));
         else {
            g_del_retry = now + 1;
            PrintFormat("❌ ยกเลิกออเดอร์รอ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         }
      }
   }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;
   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   PosMonPrune();

   // 2) ชุด T2-T4 ถูกเกี่ยวทั้ง 2 ขา → ขาแรกปิดทันที (SL ใหม่ = ราคา Stop ของขาที่ 2 = ราคาตอนนี้), ขาที่ 2 SL = ราคา Stop ของขาแรก
   ulong tkc = 0, tkf = 0;
   long  oc = 0, of = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsOurPosition()) continue;
      string c = PositionGetString(POSITION_COMMENT);
      if(SysOfComment(c) != 1) continue;
      if(StringFind(c, " F ") >= 0) { tkf = t; of = PositionGetInteger(POSITION_TIME_MSC); }
      else                          { tkc = t; oc = PositionGetInteger(POSITION_TIME_MSC); }
   }
   if(tkc != 0 && tkf != 0 && now >= g_del_retry) {
      ulong first  = (oc <= of) ? tkc : tkf;
      ulong second = (first == tkc) ? tkf : tkc;
      if(PositionSelectByTicket(first)) {
         double px1 = OrderPriceOfPosition((ulong)PositionGetInteger(POSITION_IDENTIFIER));
         if(trade.PositionClose(first)) {
            g_both_tk = second; g_both_sl = px1;
            g_last_status = StringFormat("🔁 ชุด T2-T4 ถูกเกี่ยวทั้ง 2 ขา → ปิดขาแรก #%I64u | ขาที่ 2 #%I64u SL → ราคา Stop ของขาแรก %s",
                                         first, second, DoubleToString(px1, _Digits));
            Print(g_last_status);
         } else {
            g_del_retry = now + 1;
            PrintFormat("❌ ปิดขาแรก #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", first, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         }
      }
   }

   // 3) ไม้ที่ถือ: กำไรสูงสุด → (S2 = TP / SL ที่โบรกเท่านั้น) → SL ขาที่ 2 → โหมดวิ่งยาว → ตัดจบตามเวลา → เกราะ / ไล่จี้
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      int      dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl     = PositionGetDouble(POSITION_SL);
      double   tp     = PositionGetDouble(POSITION_TP);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      string   cmt    = PositionGetString(POSITION_COMMENT);
      int      sys    = SysOfComment(cmt);
      double   prof   = (dir == 1) ? (bid - open) : (open - ask);
      double   slp    = (sl > 0.0) ? dir * (sl - open) : -1.0;
      string   kind   = KindFromComment(cmt);
      int      k      = PosMonGet(ticket, PositionGetInteger(POSITION_TIME_MSC), now_msc, prof, sys, slp, (StringFind(cmt, " F ") >= 0),
                                  (ulong)PositionGetInteger(POSITION_IDENTIFIER));
      if(prof > g_pm[k].mfe) { g_pm[k].mfe = prof; g_pm[k].mfe_msc = now_msc; }
      if(sys == 3) continue;                       // S2: TP / SL ที่โบรกเท่านั้น
      if(now_msc < g_pm[k].next_try) continue;
      if(!PositionSelectByTicket(ticket)) continue;   // PosMonGet อาจเปลี่ยนการเลือกประวัติ → เลือกไม้ใหม่

      if(ticket == g_both_tk) { g_pm[k].both = true; g_pm[k].mode = 0; g_pm[k].want_sl = g_both_sl; g_both_tk = 0; }
      if(g_pm[k].want_sl > 0.0) {   // ขาที่ 2: SL = ราคา Stop ของขาแรก
         double want = ND(g_pm[k].want_sl);
         if(MathAbs(want - sl) < _Point * 0.5) { g_pm[k].want_sl = 0.0; }
         else if(dir == 1 ? (bid <= want) : (ask >= want)) {          // ราคาเลย SL ไปแล้ว → ปิดเลย
            if(trade.PositionClose(ticket)) { PrintFormat("🔁 #%I64u ขาที่ 2 ราคาเลยราคา Stop ของขาแรกแล้ว → ปิด", ticket); continue; }
            g_pm[k].next_try = now_msc + 300; continue;
         }
         else if(dir == 1 ? (bid - want >= stops) : (want - ask >= stops)) {
            if(trade.PositionModify(ticket, want, tp)) { g_pm[k].want_sl = 0.0; sl = want; PrintFormat("🔁 #%I64u ขาที่ 2: SL → %s (ราคา Stop ของขาแรก)", ticket, DoubleToString(want, _Digits)); }
            else { g_pm[k].next_try = now_msc + 500; continue; }
         }
      }
      if(g_pm[k].mode == 0 && LongModeDue(sys, g_pm[k].both, g_pm[k].mfe)) {   // โหมดวิ่งยาว
         g_pm[k].mode = 1;
         g_last_status = StringFormat("🏃 #%I64u (%s) กำไรสูงสุด %.0f → โหมดวิ่งยาว: SL ทุน +%.0f, ตัดจบ %d แท่ง, ไล่จี้ห่าง %.0f เมื่อกำไรถึง %.0f",
                                      ticket, kind, PriceToPts(g_pm[k].mfe), InpLock1_Pts, InpLongExitBars, InpLongTrail_Pts, InpLongTrailStart_Pts);
         Print(g_last_status);
         if(sys == 1) DeletePendings("ขาที่ถูกเกี่ยวเข้าโหมดวิ่งยาว");
      }

      if(now >= ExitTimeOfN(opened, (g_pm[k].mode == 1) ? InpLongExitBars : InpExitBars)) {   // ตัดจบตามเวลา
         double pusd = PositionGetDouble(POSITION_PROFIT);
         if(trade.PositionClose(ticket)) {
            g_last_status = StringFormat("⏱️ #%I64u (%s) ตัดจบ ครบ %d แท่งหลังแท่งที่ถูกเกี่ยว | $%+.2f", ticket, kind,
                                         (g_pm[k].mode == 1) ? InpLongExitBars : InpExitBars, pusd);
            Print(g_last_status);
         } else {
            g_pm[k].next_try = now_msc + 300;
            PrintFormat("❌ ตัดจบ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         }
         continue;
      }

      int    lv;
      double target = ShieldSL(dir, open, g_pm[k].mfe, bid, ask, g_pm[k].mode, lv);   // เกราะ / ไล่จี้
      if(lv == 0) continue;
      target = ND(target);
      if(!SLBetter(dir, target, sl)) continue;
      if(lv == 4 && (now_msc - g_pm[k].last_mod < 1000 || !SLBetter(dir, target, sl + dir * PtsToPrice(InpTrailStep_Pts) - dir * _Point))) continue;
      if(dir == 1 ? (bid - target < stops) : (target - ask < stops)) continue;          // Stops Level → รอ tick ถัดไป
      if(sl > 0.0 && (dir == 1 ? (bid - sl <= freeze) : (sl - ask <= freeze))) continue; // Freeze Level
      if(trade.PositionModify(ticket, target, tp)) {
         if(g_pm[k].lock_on == 0) g_pm[k].lock_on = now_msc;
         if(lv != g_pm[k].lock_lv)
            PrintFormat("🛡️ #%I64u (%s) %s: กำไรสูงสุด %.0f → SL %s (ทุน %+.0f จุด, หลังเข้า %s)", ticket, kind,
                        (lv == 4 ? "ไล่จี้" : "เกราะขั้น " + IntegerToString(lv)), PriceToPts(g_pm[k].mfe), DoubleToString(target, _Digits),
                        dir * PriceToPts(target - open), ShortSec((now_msc - g_pm[k].open_msc) / 1000));
         g_pm[k].lock_lv  = MathMax(g_pm[k].lock_lv, lv);
         g_pm[k].last_mod = now_msc;
      } else {
         g_pm[k].next_try = now_msc + 500;
         PrintFormat("⚠️ ขยับ SL #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

//====================================================================
// ⏱️ สถิติ tick ของแท่ง (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//   1) ความเร็ว: เริ่มจับเมื่อ Z ตัวใดตัวหนึ่ง (ตัวที่สูงกว่า) ตัดขึ้นผ่าน InpSpeedFromZ ครั้งล่าสุดในแท่ง
//      → วินาทีที่แตะ T2 / T3 / T4 ครั้งแรก, แท่งเปิดมาเกินอยู่แล้ว = นับจากเวลาเปิดแท่ง (star)
//   2) K2: จำนวนครั้งที่ราคาทำยอดใหม่ของแท่ง ภายใน InpK2_Window_Sec ก่อนยอดล่าสุด (กระชาก = ทำยอดใหม่ถี่)
//====================================================================
double SpeedLevel(int k) { return (k == 0) ? InpT2_Z : (k == 1 ? InpT3_Z : InpT4_Z); }

void SpeedReset(ZSpeed &sp) {
   sp.start = 0; sp.star = false; sp.above = false; sp.seen = false; sp.z0 = 0.0;
   for(int k = 0; k < 3; k++) { sp.sec[k] = -1; sp.star_k[k] = false; }
}

void SideStatReset(SideStat &st) {
   SpeedReset(st.sp);
   st.peak_z = -99.0; st.k2 = 0; st.k2_max = 0; st.ext_px = 0.0;
}

void BarSpeedReset(BarSpeed &b, datetime bar) {
   b.bar   = bar;
   b.fresh = false;
   for(int s = 0; s < 2; s++) SideStatReset(b.sd[s]);
}

void TrackerReset(SpeedTracker &k) {
   BarSpeedReset(k.cur, 0);
   for(int s = 0; s < 2; s++) { k.tr[s].head = 0; k.tr[s].cnt = 0; }
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

// tick หนึ่งของฝั่งหนึ่ง: g = +1 SELL / −1 BUY
void SideTick(SideStat &st, SideTrack &tr, double g, double zr, double zs, double bid, long msc, long open_msc, bool fresh) {
   double ac = MathMax(g * zr, g * zs);
   SpeedTick(st.sp, ac, msc, open_msc, fresh);
   if(ac > st.peak_z) st.peak_z = ac;

   // ยอดราคาของแท่ง + K2 (เวลาที่ทำยอดใหม่ เก็บในวงแหวน ตัดอันที่เก่ากว่าหน้าต่างทิ้ง)
   bool new_ext = (st.ext_px <= 0.0) || (g > 0.0 ? bid > st.ext_px : bid < st.ext_px);
   if(!new_ext) return;
   st.ext_px  = bid;
   tr.ring[(tr.head + tr.cnt) % K2_RING] = msc;
   if(tr.cnt < K2_RING) tr.cnt++;
   else tr.head = (tr.head + 1) % K2_RING;
   long win = (long)InpK2_Window_Sec * 1000;
   while(tr.cnt > 0 && tr.ring[tr.head] < msc - win) { tr.head = (tr.head + 1) % K2_RING; tr.cnt--; }
   st.k2 = tr.cnt;
   if(tr.cnt > st.k2_max) st.k2_max = tr.cnt;
}

// อัปเดตตัวติดตามด้วย tick หนึ่ง (zr / zs = Z สด) — ขึ้นแท่งใหม่ → เก็บแท่งเดิมลงประวัติ
void TrackTick(SpeedTracker &k, double zr, double zs, double bid, long msc) {
   datetime bar = BarStartOf((datetime)(msc / 1000));
   if(bar != k.cur.bar) {
      bool fresh = (k.cur.bar != 0);   // เห็นแท่งก่อนหน้าแล้ว = tick แรกของแท่งนี้คือต้นแท่ง
      if(k.cur.bar != 0) SpeedStore(k.cur);
      BarSpeedReset(k.cur, bar);
      k.cur.fresh = fresh;
      for(int s = 0; s < 2; s++) { k.tr[s].head = 0; k.tr[s].cnt = 0; }   // K2 นับยอดใหม่ของแท่งนี้
   }
   long open_msc = (long)bar * 1000;
   SideTick(k.cur.sd[0], k.tr[0],  1.0, zr, zs, bid, msc, open_msc, k.cur.fresh);
   SideTick(k.cur.sd[1], k.tr[1], -1.0, zr, zs, bid, msc, open_msc, k.cur.fresh);
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
// 📏 Z ของแท่งที่ราคาเปิด / สูง / ต่ำ / ปิด (จาก OHLC — กล่องรายละเอียดแท่ง)
//====================================================================
// Z ของแท่ง j ที่ราคาเปิด / สูง / ต่ำ / ปิด → zr[4], zs[4] (0 O, 1 H, 2 L, 3 C)
bool BarZOHLC(const MqlRates &r[], const double &c[], int j, double &zr[], double &zs[]) {
   double px[4];
   px[0] = r[j].open; px[1] = r[j].high; px[2] = r[j].low; px[3] = r[j].close;
   for(int q = 0; q < 4; q++) if(!ZForBarPrice(c, j, px[q], zr[q], zs[q])) return false;
   return true;
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

// แถวที่ 2 ของป้าย: "เร็ว 12วิ · K2 7"
string BarInfoText(int side, bool has, const SideStat &st) {
   if(!has) return "";
   string s = "";
   if(st.sp.sec[0] >= 0) s += "เร็ว " + SpeedCell(st.sp, 0);
   if(st.k2 > 0)         s += (s == "" ? "" : " · ") + "K2 " + IntegerToString(st.k2);
   return s;
}

// วาด/ลบป้าย Z ของแท่ง — แถว 1 (ติดแท่ง): Z_reg / Z_SMA / Z_float, แถว 2: เร็ว / K2
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
         tip += StringFormat("\nเร็ว (Z ตัวใดก็ได้ จาก %.1f) → %s | K2 %d (สูงสุด %d)", InpSpeedFromZ, SpeedLong(st.sp), st.k2, st.k2_max);
      tip += "\nชี้เมาส์ที่แท่งเพื่อดูรายละเอียดทั้งหมด (มุมซ้ายล่าง)";
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);

      string itx = InpShowZSpeed ? BarInfoText(side, has, st) : "";
      if(itx == "") { DeleteLabel(info); continue; }
      EnsureBarText(info, v.t, price, side == 0, InpClrBarZInfo, false);
      SetLabelText(info, itx);
      ObjectSetString(0, info, OBJPROP_TOOLTIP, tip);
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
   MqlRates r[];
   double   c[];
   int got = CopyRates(_Symbol, InpZ_Timeframe, from_shift, cnt, r);
   if(got < n + 1) return;
   ArrayResize(c, got);
   for(int i = 0; i < got; i++) c[i] = r[i].close;
   for(int j = MathMax(n - 1, got - bars); j < got; j++) {
      BarView v;
      v.t = r[j].time; v.hi = r[j].high; v.lo = r[j].low; v.open = r[j].open;
      v.ok[0] = ZForBarPrice(c, j, r[j].high, v.zr[0], v.zs[0]);
      v.ok[1] = ZForBarPrice(c, j, r[j].low,  v.zr[1], v.zs[1]);
      double sma = 0.0, sd = 0.0;
      v.fz = SmaSdAt(c, j, r[j].open, sma, sd) ? (r[j].open - sma) / sd : 0.0;
      SetBarZLabels(v);
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
   if(!g_draw || !InpShowBarZ || !g_z_ready) return;
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
   }
   SetBarZLabels(v);
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
   long     pos_id;        // โพซิชันของดีลเปิดนี้
   bool     mfe_ok;        // คำนวณกำไรสูงสุดแล้ว
   bool     mfe_done;      // ไม้ปิดแล้ว ค่ากำไรสูงสุดคงที่
   double   mfe;           // กำไรสูงสุดระหว่างถือ (ราคา, จากแท่ง M1)
   long     mfe_sec;       // ถึงกำไรสูงสุดหลังเข้า (วินาที, ละเอียดระดับนาที)
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
   int    tier_m = TierFromComment(m.cmt);
   string mfe_s  = m.mfe_ok ? StringFormat(" | สูงสุด %+.0f @%s%s", PriceToPts(m.mfe), ShortSec(m.mfe_sec), (m.mfe_done ? "" : " (ถืออยู่)")) : "";
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("   %s%s %s | %s | ห่างไส้ %.0f%s", (tier_m > 0 ? StageTag(tier_m) + " " : ""), KindFromComment(m.cmt), (is_sell ? "S" : "B"),
                                                    BarMinText(m.t), gap_pts, mfe_s));

   string tipText = StringFormat("%s @ %s | %s แท่ง %s = %s | ห่างปลายไส้ %.0f จุด (%.0f%% ของช่วงแท่ง)%s | %s",
                                 (is_sell ? "SELL" : "BUY"), DoubleToString(m.price, _Digits),
                                 (is_sell ? "High" : "Low"), TimeToString(bt, TIME_DATE|TIME_MINUTES),
                                 DoubleToString(tip, _Digits), gap_pts, (range > 0.0 ? 100.0 * gap / range : 0.0),
                                 (shift == 0 ? " (แท่งยังไม่ปิด)" : ""), m.cmt);
   if(m.mfe_ok)
      tipText += StringFormat("\nกำไรสูงสุดระหว่างถือ %+.0f จุด ถึงหลังเข้า %s (คำนวณจากแท่ง M1 — ละเอียดระดับนาที)", PriceToPts(m.mfe), ShortSec(m.mfe_sec));
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
   g_marks[n].pos_id   = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   g_marks[n].mfe_ok   = false;
   g_marks[n].mfe_done = false;
   g_marks[n].mfe      = 0.0;
   g_marks[n].mfe_sec  = 0;
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
// กำไรสูงสุดของไม้จริงจากแท่ง M1 ตั้งแต่นาทีที่เข้าถึงตอนออก (ถืออยู่ = ถึงตอนนี้) — true = ค่าเปลี่ยน
bool UpdateMarkMFE(EntryMark &m) {
   bool     open  = PositionSelectByTicket((ulong)m.pos_id);
   datetime t_end = TimeCurrent();
   if(!open) {
      if(!HistorySelectByPosition(m.pos_id)) return false;
      t_end = 0;
      for(int k = 0; k < HistoryDealsTotal(); k++) {
         ulong d = HistoryDealGetTicket(k);
         if(d == 0 || HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         datetime td = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         if(td > t_end) t_end = td;
      }
      if(t_end == 0) return false;
   }
   MqlRates r[];
   int got = CopyRates(_Symbol, PERIOD_M1, m.t - (datetime)((long)m.t % 60), t_end, r);
   if(got <= 0) return false;
   double   best = 0.0;
   datetime bt   = m.t;
   for(int k = 0; k < got; k++) {
      double fav = (m.dir == -1) ? (m.price - r[k].low) : (r[k].high - m.price);
      if(fav > best) { best = fav; bt = r[k].time; }
   }
   bool changed = (!m.mfe_ok || MathAbs(best - m.mfe) > _Point * 0.5 || m.mfe_done != !open);
   m.mfe      = best;
   m.mfe_sec  = MathMax(0, (long)(bt - m.t));
   m.mfe_ok   = true;
   m.mfe_done = !open;
   return changed;
}

void UpdateEntryMarks() {
   if(!g_draw || !InpShowEntryMarks) return;
   for(int i = ArraySize(g_marks) - 1; i >= 0; i--) {
      bool redraw = !g_marks[i].closed_bar;
      if(!g_marks[i].mfe_done && UpdateMarkMFE(g_marks[i])) { redraw = true; g_lbl_ver++; }
      if(redraw) DrawEntryMark(g_marks[i]);
   }

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
//   (ชุด T2-T4 Stop 2 ขา / ชุด T5 เปิดแท่งใหม่ / ชุด S2 สวนที่ไส้ / เวลาตลาด / สเปรด / ตัดจบ 2 แท่ง / เกราะ 3 ขั้น / ปิดสุดสัปดาห์)
//====================================================================
#define RX_OPEN   0   // ถูกเกี่ยวแล้ว ถืออยู่
#define RX_TIME   1   // ตัดจบตามเวลา
#define RX_SL     2
#define RX_WEEK   3   // บังคับปิดก่อนตลาดปิดสัปดาห์
#define RX_PEND   4   // ออเดอร์รอ (ยังไม่ถูกเกี่ยว)
#define RX_EXP    5   // ไม่ถูกเกี่ยวจนครบอายุ → ยกเลิก
#define RX_LOCK   6   // ชน SL ที่เกราะกำไรขยับแล้ว
#define RX_FLIP   7   // ชุด T2-T4 ถูกเกี่ยวทั้ง 2 ขา → ปิดขาแรก (v14.90)
#define RX_TRAIL  8   // ชนโล่ไล่จี้ (โหมดวิ่งยาว)
#define RX_TP     9   // ถึง TP (S2)

// ไม้จำลอง 1 ขา (ชุดละ 2 ขา: kind 0 = สวนกลับ / 1 = ตามน้ำ)
struct RTrade {
   int      set_id;        // รหัสชุด (สัญญาณเดียวกัน)
   int      kind;          // 0 = สวน (Stop) / 1 = ตาม (Stop) / 2 = T5 สวน (Market) / 3 = S2 สวนที่ไส้ (Market)
   int      sl_mode;       // ที่มาของ SL (SLM_*)
   int      sig_dir;       // ทิศของฝั่งสวน (−1 = สัญญาณ SELL จาก Z ขึ้น / +1 = สัญญาณ BUY)
   long     msc_sig;       // เวลาสัญญาณ (วางออเดอร์)
   double   p_order;       // ราคา Stop
   long     exp_msc;       // ยกเลิกถ้ายังไม่ถูกเกี่ยวเมื่อถึงเวลานี้ (จบแท่งสัญญาณ / ช่วงห้ามเข้าก่อนปิดสัปดาห์)
   long     exit_msc;      // ตัดจบตามเวลา (หลังถูกเกี่ยว)
   long     msc_in;
   int      dir;
   int      stage;         // ระดับที่ยิง (2-5, S2 = 0)
   int      max_tier;      // ระดับลึกสุดระหว่างเฝ้า
   double   lot;
   double   p_in, sl, tp;
   double   zr, zs, ext_r, ext_s;
   double   mfe, mae;      // กำไรสูงสุด / ติดลบสูงสุดระหว่างถือ (ราคา)
   long     mfe_msc;       // เวลาที่ทำกำไรสูงสุด
   int      lock_lv;       // ขั้นเกราะที่ขยับ SL แล้ว (0 = ยัง)
   long     lock_on_msc;   // เวลาที่เกราะขยับ SL ครั้งแรก (0 = ยัง)
   int      mode;          // 0 = ปกติ / 1 = วิ่งยาว (T2-T4 เกี่ยวฝั่งเดียว / T5)
   bool     both;          // T2-T4: ขาที่ 2 ของชุดที่ถูกเกี่ยวทั้ง 2 ขา
   long     last_mod;      // ขยับ SL ไล่จี้ล่าสุด (msc)
   double   sl0;           // SL ตอนเปิดไม้ (ก่อนขยับโล่)
   double   peak;          // High (SELL) / Low (BUY) ของแท่ง ณ ตอนเปิดไม้ ที่ใช้วาง SL
   int      bar_seq;       // ไม้ลำดับที่เท่าไหร่ของแท่ง (ทุกฝั่ง)
   double   z_float;                      // แท่งลอยตัว: ราคาเปิด เทียบ SMA ตอนเปิดแท่ง ÷ SD20 (+ = ทิศของการกระชาก)
   SideStat ss;                           // สถิติ tick ของแท่ง ณ ตอนสัญญาณ (ฝั่งกระชาก): ความเร็ว / K2
   bool     ss_ok;                        // มีข้อมูล tick ของแท่งนี้
   double   zb[6];                        // Z ของแท่งจนถึงตอนสัญญาณ: Z_reg เปิด / สูง / ต่ำ, Z_SMA เปิด / สูง / ต่ำ
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

RTrade     g_rt[];
RBlocked   g_rb[];
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
int        g_t5_leg       = -1;      // index ใน g_rt ของไม้ T5 ที่ถืออยู่ (−1 = ไม่มี)
int        g_s2_leg       = -1;      // index ใน g_rt ของไม้ S2 ที่ถืออยู่ (−1 = ไม่มี)
S2State    g_rp_s2;                  // S2 ของแท่งที่กำลังเล่น
datetime   g_rp_set_bar   = 0;       // แท่งที่วางชุด T2-T4 ล่าสุด (Tick Replay)
int        g_rp_t5_cur    = 0;       // T5: แท่งที่กำลังเล่นแตะ > T5 แล้ว (ทิศของไม้สวน)
double     g_rp_t5_cur_z  = 0.0;
int        g_rp_t5_pend   = 0;       // T5: รอเปิดในแท่งนี้ (จากแท่งก่อน)
double     g_rp_t5_pend_z = 0.0;
long       g_rp_t5_until  = 0;       // T5: ลองเปิดได้ถึงเวลานี้ (msc)
int        g_rp_csv_rows  = -1;      // จำนวนไม้ที่เขียนลง CSV ล่าสุด
double     g_rp_bid = 0.0, g_rp_ask = 0.0, g_rp_zr = 0.0, g_rp_zs = 0.0;
double     g_rp_fz        = 0.0;     // Z_float ของแท่งที่กำลังเล่น (ราคาเปิด เทียบ SMA ตอนเปิดแท่ง, + = เหนือ SMA)
long       g_rp_msc       = 0;
bool       g_rp_have      = false;
bool       g_rp_init      = false;
bool       g_rp_caught    = false;
long       g_rp_cursor    = 0;
int        g_rp_retry     = 0;
MqlTick    g_rp_buf[];               // tick ของช่วงที่โหลดแล้ว รอเล่น (เล่นทีละส่วนตามงบเวลา)
int        g_rp_buf_i     = 0;
int        g_rp_buf_n     = 0;
long       g_rp_buf_to    = 0;       // ปลายช่วงของบัฟเฟอร์ปัจจุบัน (msc)
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
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false; g_rp_bar_chg = false; g_rp_hi = 0.0; g_rp_lo = 0.0;
   WatchReset(g_rp_ws); WatchReset(g_rp_wb);
   g_t5_leg = -1; g_s2_leg = -1;
   S2Clear(g_rp_s2);
   g_rp_t5_cur = 0; g_rp_t5_cur_z = 0.0; g_rp_t5_pend = 0; g_rp_t5_pend_z = 0.0; g_rp_t5_until = 0;
   g_rp_set_bar = 0;
   g_rp_csv_rows = -1;
   g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_zr = 0.0; g_rp_zs = 0.0;
   g_rp_msc = 0; g_rp_have = false; g_rp_init = false; g_rp_caught = false;
   g_rp_cursor = 0; g_rp_retry = 0; g_rp_ticks = 0;
   g_rp_fail_cur = -1; g_rp_fail_ms = 0; g_rp_skip_n = 0; g_rp_skip_txt = "";
   ArrayResize(g_rp_buf, 0); g_rp_buf_i = 0; g_rp_buf_n = 0; g_rp_buf_to = 0;
   g_rp_status = "ยังไม่เริ่ม";
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
   int    n = InpZ_Period;
   double c[];
   if(b >= n) {
      ArrayResize(c, n);
      for(int i = 0; i < n; i++) c[i] = g_rr[b - n + i].close;
      BuildZCache(c, g_rp_zc);
   }
   double fsma, fsd;
   g_rp_fz = FloatAtOpen(g_rp_zc, g_rr[b].open, fsma, fsd);
   if(b >= n) S2NewBar(g_rp_s2, g_rr[b].time, c, g_rr[b - 1], 0.0, 0.0);   // S2: บริบทของแท่งปิดล่าสุด
   else       S2Clear(g_rp_s2);
   if(had) {   // T5: แท่งที่เพิ่งจบแตะ > T5 → รอเปิดในแท่งนี้
      g_rp_bar_chg   = true;
      g_rp_t5_pend   = g_rp_t5_cur;
      g_rp_t5_pend_z = g_rp_t5_cur_z;
      g_rp_t5_until  = ((long)g_rr[b].time + InpT5_RetrySec) * 1000;
   } else g_rp_t5_pend = 0;
   g_rp_t5_cur = 0; g_rp_t5_cur_z = 0.0;
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
//   ค่าตอนสัญญาณ (Z / Z_float / สถิติแท่ง) บันทึกเหมือนกันทั้ง 2 ขา
int ReplayAddLeg(int sig_dir, int kind, int stage, long msc, double order_px, double sl, long exp_msc, int set_id) {
   int i = ArraySize(g_rt);
   ArrayResize(g_rt, i + 1, 256);
   int      dir = (kind == 1) ? -sig_dir : sig_dir;
   double   hi  = (g_rp_hi > 0.0) ? MathMax(g_rp_hi, g_rp_bid) : g_rp_bid;
   double   lo  = (g_rp_lo > 0.0) ? MathMin(g_rp_lo, g_rp_bid) : g_rp_bid;
   datetime bar = BarStartOf((datetime)(msc / 1000));
   if(dir == 1) sl = MathMin(sl, order_px - _Point);   // SL ต้องอยู่ฝั่งขาดทุนของราคาเข้า
   else         sl = MathMax(sl, order_px + _Point);
   g_rt[i].set_id   = set_id;
   g_rt[i].kind     = kind;
   g_rt[i].sl_mode  = (kind == 1) ? SLM_TREND : ((kind == 2) ? SLM_FIXED : ((kind == 3) ? SLM_S2 : SLM_PEAK));
   g_rt[i].mfe_msc  = 0;
   g_rt[i].lock_lv  = 0; g_rt[i].lock_on_msc = 0;
   g_rt[i].mode     = 0; g_rt[i].both = false; g_rt[i].last_mod = 0;
   g_rt[i].sig_dir  = sig_dir;
   g_rt[i].msc_sig  = msc;
   g_rt[i].p_order  = order_px;
   g_rt[i].exp_msc  = exp_msc;
   g_rt[i].exit_msc = 0;
   g_rt[i].msc_in   = 0;
   g_rt[i].dir      = dir;
   g_rt[i].stage    = stage;
   g_rt[i].lot      = (kind == 3) ? NormalizeLot(InpS2_Lot) : TierLot(stage);
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
   g_rt[i].z_float  = ZFloat(sig_dir, g_rp_fz);
   int side = (sig_dir == -1) ? 0 : 1;   // ฝั่งของการกระชาก (สัญญาณ SELL = Z ขึ้น)
   g_rt[i].ss_ok    = (g_trk_rp.cur.bar == bar);
   if(g_rt[i].ss_ok) g_rt[i].ss = g_trk_rp.cur.sd[side];
   else              SideStatReset(g_rt[i].ss);
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
   g_rt[i].mfe = 0.0; g_rt[i].mae = 0.0; g_rt[i].mfe_msc = msc;
   g_rt[i].lock_lv = 0; g_rt[i].lock_on_msc = 0;
   g_rt[i].pa_sum = 0.0; g_rt[i].pa_ms = 0.0; g_rt[i].pa_fav = 0.0; g_rt[i].pa_msc = msc;
   g_rt[i].force_close = ForceCloseTimeAt(t);
   g_rt[i].exit_msc    = (g_rt[i].kind == 3) ? LONG_MAX : (long)ExitTimeOf(t) * 1000;   // S2: TP / SL เท่านั้น
   g_lbl_ver++;   // มีป้ายไม้ใหม่ → จัดตำแหน่งป้ายใหม่
}

bool RDone(int r) { return (r == RX_TIME || r == RX_SL || r == RX_WEEK || r == RX_LOCK || r == RX_FLIP || r == RX_TRAIL || r == RX_TP); }

// ชุด T2-T4 จบ = ไม่เหลือขาที่รอ / ถือ → เริ่มหาสัญญาณใหม่ | ไม้ T5 / S2 ปิด → ชุดนั้นเปิดใหม่ได้
void ReplaySetCheck() {
   if(g_t5_leg >= 0 && RDone(g_rt[g_t5_leg].reason)) g_t5_leg = -1;
   if(g_s2_leg >= 0 && RDone(g_rt[g_s2_leg].reason)) g_s2_leg = -1;
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

//   ครบเวลาเฝ้า → ชุด Stop 2 ฝั่ง (สวน + ตาม)
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
   // วางชุด: สวน (ทิศ dir) + ตาม (ทิศตรงข้าม) ห่างฝั่งละ InpStopDist_Pts, หมดอายุเมื่อครบ InpStopExpire_Min นาที / เข้าช่วงห้ามเข้าก่อนปิดสัปดาห์
   double   hi   = (g_rp_hi > 0.0) ? MathMax(g_rp_hi, g_rp_bid) : g_rp_bid;
   double   lo   = (g_rp_lo > 0.0) ? MathMin(g_rp_lo, g_rp_bid) : g_rp_bid;
   double   dist = PtsToPrice(InpStopDist_Pts);
   long     exp_ms = fire_msc + (long)InpStopExpire_Min * 60000;
   datetime nc     = NoEntryStartAt(t);
   if(nc > 0) exp_ms = MathMin(exp_ms, (long)nc * 1000);
   double   ec    = (dir == 1) ? g_rp_ask + dist : g_rp_bid - dist;   // ราคาเข้าของขาสวน / ขาตาม
   double   ef    = (dir == 1) ? g_rp_bid - dist : g_rp_ask + dist;
   int      mc, mf;
   double   slc   = CounterSL(dir, ec, hi, lo, mc);
   double   slf   = TrendSL(-dir, ef, mf);
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
   }
   g_set_on     = true;
   g_rp_set_bar = g_rp_bar_t;
   g_set_leg[0] = ic;
   g_set_leg[1] = itf;
   WatchReset(g_rp_ws);
   WatchReset(g_rp_wb);
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
void ReplayBlock(long msc, int dir, double price, string why) {
   int k = ArraySize(g_rb);
   ArrayResize(g_rb, k + 1);
   g_rb[k].msc = msc; g_rb[k].dir = dir; g_rb[k].price = price; g_rb[k].why = why;
}

void ReplayTimeEvents(long msc) {
   if(!g_rp_have) return;
   // ทุกชุด: ออเดอร์รอหมดอายุ / บังคับปิดสุดสัปดาห์ (ราคาของ tick ก่อนหน้า)
   int legs[4];
   legs[0] = g_set_leg[0]; legs[1] = g_set_leg[1]; legs[2] = g_t5_leg; legs[3] = g_s2_leg;
   for(int m = 0; m < 4; m++) {
      int i = legs[m];
      if(i < 0) continue;
      if(g_rt[i].reason == RX_PEND && msc >= g_rt[i].exp_msc) { g_rt[i].reason = RX_EXP; g_rt[i].msc_out = g_rt[i].exp_msc; }
      else if(g_rt[i].reason == RX_OPEN) {
         long wk = (g_rt[i].force_close > 0) ? (long)g_rt[i].force_close * 1000 : LONG_MAX;
         if(wk <= msc) ReplayClose(i, wk, (g_rt[i].dir == -1) ? g_rp_ask : g_rp_bid, RX_WEEK);
      }
   }
   ReplaySetCheck();
   // ชุด T2-T4: ครบเวลาเฝ้า → วางชุด (ชุดเดิมยังไม่จบ = ไม่หาสัญญาณใหม่)
   if(!g_set_on && !SetBarUsed(g_rp_set_bar, g_rp_bar_t)) {
      if(WatchReady(g_rp_ws, msc))      ReplayFire(-1, MathMax(WatchDeadline(g_rp_ws), g_rp_msc));
      else if(WatchReady(g_rp_wb, msc)) ReplayFire( 1, MathMax(WatchDeadline(g_rp_wb), g_rp_msc));
   }
   // ชุด S2: ครบเวลาไม่มียอดใหม่ (ภายในแท่งของสัญญาณ, ราคาของ tick ก่อนหน้า) — ครั้งเดียวต่อแท่ง, ทีละ 1 ไม้
   if(g_en[6] && !g_rp_s2.done && g_s2_leg < 0 && g_rp_s2.bar > 0) {
      long bar_end = ((long)g_rp_s2.bar + PeriodSeconds(InpZ_Timeframe)) * 1000;
      int  d       = S2Ready(g_rp_s2, MathMin(msc, bar_end - 1));
      if(d != 0) {
         long   fire = MathMax(S2Deadline(g_rp_s2, (d == -1) ? 0 : 1), g_rp_msc);
         double px   = (d == -1) ? g_rp_bid : g_rp_ask;
         string why  = EntryBlockReason(GetTimeStateAt((datetime)(fire / 1000)), g_rp_bid, g_rp_ask);
         g_rp_s2.done = true;
         if(why != "") ReplayBlock(fire, d, px, "S2: " + why);
         else {
            double sl, tp, dist;
            if(!S2Plan(g_rp_s2, d, g_rp_bid, g_rp_ask, sl, tp, dist)) { ReplayBlock(fire, d, px, StringFormat("S2: ระยะ SL %.0f > %.0f จุด", PriceToPts(dist), InpS2_MaxSL_Pts)); return; }
            int i = ReplayAddLeg(d, 3, 0, fire, px, sl, 0, 0);
            g_rt[i].tp    = tp;
            g_rt[i].ext_r = (d == -1) ? g_rp_s2.p_zhi : g_rp_s2.p_zlo;
            g_rt[i].ext_s = g_rt[i].ext_r;
            ReplayFill(i, fire, px);
            g_s2_leg = i;
         }
      }
   }
}

// ขาของชุด + ไม้ T5 ด้วยราคา tick ปัจจุบัน: ออเดอร์รอ → ถูกเกี่ยว (Buy Stop: Ask ≥ ราคา / Sell Stop: Bid ≤ ราคา, ได้ราคาของ tick)
//   ไม้ที่ถือ → SL / เกราะ → กำไรสูงสุด → ตัดจบ (tick แรกของแท่งถัดจากแท่งที่ InpExitBars) → ขยับเกราะ

void ReplayManageTick(long msc, double bid, double ask) {
   int legs[4];
   legs[0] = g_set_leg[0]; legs[1] = g_set_leg[1]; legs[2] = g_t5_leg; legs[3] = g_s2_leg;
   for(int m = 0; m < 4; m++) {
      int i = legs[m];
      if(i < 0) continue;
      int d = g_rt[i].dir;
      if(g_rt[i].reason == RX_PEND) {
         bool hit = (d == 1) ? (ask >= g_rt[i].p_order) : (bid <= g_rt[i].p_order);
         if(!hit) continue;
         ReplayFill(i, msc, (d == 1) ? ask : bid);
         int o = (m < 2) ? legs[1 - m] : -1;   // ชุด T2-T4 ถูกเกี่ยวทั้ง 2 ขา → ขาแรกปิดทันที, ขานี้ SL = ราคา Stop ของขาแรก
         if(o >= 0 && g_rt[o].reason == RX_OPEN) {
            double fo = (g_rt[o].dir == -1) ? (g_rt[o].p_in - ask) : (bid - g_rt[o].p_in);
            ProfitAvgAdd(o, msc, fo);
            ReplayClose(o, msc, (g_rt[o].dir == -1) ? ask : bid, RX_FLIP);
            double sl2 = g_rt[o].p_order;
            g_rt[i].sl   = (d == 1) ? MathMin(sl2, g_rt[i].p_in - _Point) : MathMax(sl2, g_rt[i].p_in + _Point);
            g_rt[i].both = true;
         }
      }
      if(g_rt[i].reason != RX_OPEN) continue;
      double fav = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
      double px = (d == -1) ? ask : bid;
      if(d == -1 ? (ask >= g_rt[i].sl) : (bid <= g_rt[i].sl)) {   // SL (ชนก่อนขยับเกราะด้วยราคานี้)
         ProfitAvgAdd(i, msc, fav);
         ReplayClose(i, msc, px, (g_rt[i].lock_lv == 4) ? RX_TRAIL : ((g_rt[i].lock_lv > 0) ? RX_LOCK : RX_SL));
         continue;
      }
      if(g_rt[i].tp > 0.0 && (d == -1 ? (ask <= g_rt[i].tp) : (bid >= g_rt[i].tp))) {   // TP (S2) ได้ราคา TP
         ProfitAvgAdd(i, msc, fav);
         ReplayClose(i, msc, g_rt[i].tp, RX_TP);
         continue;
      }
      if(fav > g_rt[i].mfe) { g_rt[i].mfe = fav; g_rt[i].mfe_msc = msc; }
      if(fav < g_rt[i].mae) g_rt[i].mae = fav;
      ProfitAvgAdd(i, msc, fav);
      if(g_rt[i].kind == 3) continue;   // S2: TP / SL เท่านั้น
      int sys = (g_rt[i].kind == 2) ? 2 : 1;
      if(g_rt[i].mode == 0 && LongModeDue(sys, g_rt[i].both, g_rt[i].mfe)) {   // โหมดวิ่งยาว: ตัดจบ 4 แท่ง + ลบ Stop อีกฝั่งที่รอ
         g_rt[i].mode     = 1;
         g_rt[i].exit_msc = (long)ExitTimeOfN((datetime)(g_rt[i].msc_in / 1000), InpLongExitBars) * 1000;
         int o = (m < 2) ? legs[1 - m] : -1;
         if(o >= 0 && g_rt[o].reason == RX_PEND) { g_rt[o].reason = RX_EXP; g_rt[o].msc_out = msc; }
      }
      if(msc >= g_rt[i].exit_msc) { ReplayClose(i, msc, px, RX_TIME); continue; }
      int    lv;
      double target = ShieldSL(d, g_rt[i].p_in, g_rt[i].mfe, bid, ask, g_rt[i].mode, lv);   // เกราะ / ไล่จี้ (ขยับทางเดียว)
      if(lv == 0 || !SLBetter(d, target, g_rt[i].sl)) continue;
      if(lv == 4 && (msc - g_rt[i].last_mod < 1000 || !SLBetter(d, target, g_rt[i].sl + d * PtsToPrice(InpTrailStep_Pts) - d * _Point))) continue;
      g_rt[i].sl       = target;
      g_rt[i].lock_lv  = MathMax(g_rt[i].lock_lv, lv);
      g_rt[i].last_mod = msc;
      if(g_rt[i].lock_on_msc == 0) g_rt[i].lock_on_msc = msc;
   }
   ReplaySetCheck();
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
   if(zok) {   // Z ล่าสุด + สถิติ tick ของแท่ง (ก่อนวาง → ชุดที่วางใน tick ถัดไปเห็นค่าล่าสุด)
      g_rp_zr = zr; g_rp_zs = zs;
      TrackTick(g_trk_rp, zr, zs, bid, msc);
      T5Touch(g_rp_t5_cur, g_rp_t5_cur_z, zr, zs);
   }
   S2Tick(g_rp_s2, bid, msc);

   if(g_set_on || g_t5_leg >= 0 || g_s2_leg >= 0) ReplayManageTick(msc, bid, ask);   // C) ชุด T2-T4 (รอ / ถือ) + ไม้ T5 + ไม้ S2

   if(g_rp_t5_pend != 0) {   // ชุด T5: เปิด Market สวนตอนแท่งใหม่ด้วยราคาของ tick นี้ (ไม่ต่อคิวชุดอื่น, ทีละ 1 ไม้)
      int    d   = g_rp_t5_pend;
      double px  = (d == -1) ? bid : ask;
      string why = EntryBlockReason(GetTimeStateAt(t), bid, ask);
      if(!g_en[5] || g_t5_leg >= 0) g_rp_t5_pend = 0;
      else if(msc > g_rp_t5_until) { ReplayBlock(msc, d, px, StringFormat("T5: ติดตัวกรองเกิน %d วิแรกของแท่ง (%s)", InpT5_RetrySec, why)); g_rp_t5_pend = 0; }
      else if(why == "") {
         double sl = px - d * PtsToPrice(InpT5_SL_Pts);
         int    i  = ReplayAddLeg(d, 2, 5, msc, px, sl, 0, 0);
         g_rt[i].ext_r = g_rp_t5_pend_z;
         g_rt[i].ext_s = g_rp_t5_pend_z;
         ReplayFill(i, msc, px);
         g_t5_leg     = i;
         g_rp_t5_pend = 0;
      }
   }

   // D) เฝ้ายอดราคา (ชุด T2-T4): ขึ้นแท่งใหม่ / ชุดนี้ยังไม่จบ = ล้างการเฝ้า — เวลาตลาด / สเปรด ตรวจตอนวาง
   bool active = g_set_on || SetBarUsed(g_rp_set_bar, g_rp_bar_t);   // 1 ชุด/แท่ง
   if(!zok || g_rp_bar_chg || active) { WatchReset(g_rp_ws); WatchReset(g_rp_wb); }
   if(zok && !active) {
      WatchUpdate(g_rp_ws, -1, zr, zs, msc, bid, ask, ZFloat(-1, g_rp_fz));
      WatchUpdate(g_rp_wb,  1, zr, zs, msc, bid, ask, ZFloat( 1, g_rp_fz));
   }
   g_rp_bar_chg = false;

   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc;
   g_rp_have = true;
   g_rp_ticks++;
}

string ReplayReasonName(int r) {
   switch(r) {
      case RX_TIME: return "ตัดจบ";
      case RX_SL:   return "SL";
      case RX_WEEK: return "ปิดสัปดาห์";
      case RX_PEND: return "รอ";
      case RX_EXP:  return "ไม่ถูกเกี่ยว";
      case RX_LOCK:   return "เกราะ";
      case RX_FLIP:   return "ตัดขาแรก";
      case RX_TRAIL:  return "ไล่จี้";
      case RX_TP:     return "TP";
   }
   return "ถืออยู่";
}

void DrawReplayTrade(int i) {
   bool     is_sell = (g_rt[i].dir == -1);
   string   kname   = (g_rt[i].kind == 1) ? "ตาม" : ((g_rt[i].kind == 3) ? "ไส้" : "สวน");
   string   tag     = (g_rt[i].kind == 3) ? "S2" : StageTag(g_rt[i].stage);
   int      r       = g_rt[i].reason;
   bool     filled  = (g_rt[i].msc_in > 0);
   datetime t_sig   = (datetime)(g_rt[i].msc_sig / 1000);
   datetime t_in    = (datetime)(g_rt[i].msc_in / 1000);
   string   otype   = (g_rt[i].kind >= 2) ? (is_sell ? "SELL (Market)" : "BUY (Market)") : (is_sell ? "SELL STOP" : "BUY STOP");
   string   slwhy   = SLModeText(g_rt[i].sl_mode);

   // 1) ระดับ Stop: เส้นจากเวลาสัญญาณ → ถูกเกี่ยว / หมดอายุ (T5 Market ไม่มี)
   string   np    = OBJ_PREFIX + "RP_P_" + IntegerToString(g_rt[i].msc_sig) + "_" + IntegerToString(i);
   if(g_rt[i].kind < 2) {
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
   }
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
   string mfe_s = StringFormat(" | สูงสุด %+.0f @%s", PriceToPts(g_rt[i].mfe), ShortSec((g_rt[i].mfe_msc - g_rt[i].msc_in) / 1000));
   ObjectSetString(0, nt, OBJPROP_TEXT,
                   open ? StringFormat("%s %s %s %.2f | %s | ถืออยู่%s   ", tag, kname, (is_sell ? "S" : "B"), g_rt[i].lot, BarMinText(t_in), mfe_s)
                        : StringFormat("%s %s %s %.2f | %s | %s %+.0f ($%+.2f)%s   ", tag, kname, (is_sell ? "S" : "B"), g_rt[i].lot,
                                       BarMinText(t_in), ReplayReasonName(r), g_rt[i].pnl, g_rt[i].usd, mfe_s));

   string tipText = StringFormat("จำลอง %s %s %s: %s %.2f lot | สั่ง @ %s → ได้ %s (%s, %s ของแท่ง) | SL %s (%s)",
                                 (g_rt[i].kind >= 2 ? "Market" : "ชุด #" + IntegerToString(g_rt[i].set_id)), tag, kname, otype, g_rt[i].lot, DoubleToString(g_rt[i].p_order, _Digits),
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
               + StringFormat("\nระยะกำไรระหว่างถือ: ต่ำสุด %+.0f / สูงสุด %+.0f (ถึงหลังเข้า %s) / เฉลี่ย %+.0f จุด",
                              PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ShortSec((g_rt[i].mfe_msc - g_rt[i].msc_in) / 1000), ProfitAvgPts(i));
   tipText += StringFormat("\nZ_float %+.2f (ราคาเปิด vs SMA ตอนเปิดแท่ง, + = ทิศกระชาก)", g_rt[i].z_float);
   if(g_rt[i].ss_ok)
      tipText += StringFormat("\nเร็ว (Z ตัวใดก็ได้ จาก %.1f) → %s | K2 %d", InpSpeedFromZ, SpeedLong(g_rt[i].ss.sp), g_rt[i].ss.k2);
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
   int    n = 0, w = 0, c_tm = 0, c_sl = 0, c_wk = 0, c_lk = 0, c_fl = 0, c_tr = 0, c_tp = 0;
   int    kn[4];
   int    kw[4];
   double ku[4];
   int    cnt[6];
   double usd_st[6];
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
      if(g_rt[i].kind < 3) {
         int st = MathMax(1, MathMin(5, g_rt[i].stage));
         cnt[st]++;
         usd_st[st] += g_rt[i].usd;
      }
      int k = g_rt[i].kind;
      kn[k]++; ku[k] += g_rt[i].usd; if(g_rt[i].usd > 0.0) kw[k]++;
      switch(g_rt[i].reason) {
         case RX_TIME: c_tm++; break;
         case RX_SL:   c_sl++; break;
         case RX_WEEK: c_wk++; break;
         case RX_LOCK:   c_lk++; break;
         case RX_FLIP:   c_fl++; break;
         case RX_TRAIL:  c_tr++; break;
         case RX_TP:     c_tp++; break;
      }
   }
   int sr[5];
   ArrayInitialize(sr, 0);
   for(int i = 0; i < ArraySize(g_rt); i++) if(g_rt[i].kind == 0) sr[SetResult(i)]++;
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | SL %d เกราะ %d ไล่จี้ %d TP %d ตัดจบ %d ตัดขาแรก %d ปิดสัปดาห์ %d | ถูกทิ้ง %d",
                           InpReplayDays, g_rp_status, n, (n > 0 ? 100.0 * w / n : 0.0), usd, dd,
                           c_sl, c_lk, c_tr, c_tp, c_tm, c_fl, c_wk, ArraySize(g_rb));
   s += StringFormat("\n   สวน %d ไม้ ชนะ %.0f%% $%+.2f | ตาม %d ไม้ ชนะ %.0f%% $%+.2f | T5 %d ไม้ ชนะ %.0f%% $%+.2f | S2 %d ไม้ ชนะ %.0f%% $%+.2f",
                     kn[0], (kn[0] > 0 ? 100.0 * kw[0] / kn[0] : 0.0), ku[0], kn[1], (kn[1] > 0 ? 100.0 * kw[1] / kn[1] : 0.0), ku[1],
                     kn[2], (kn[2] > 0 ? 100.0 * kw[2] / kn[2] : 0.0), ku[2], kn[3], (kn[3] > 0 ? 100.0 * kw[3] / kn[3] : 0.0), ku[3]);
   s += StringFormat("\n   ชุด T2-T4 %d ชุด: ไม่ถูกเกี่ยว %d | เกี่ยวขาสวน %d | เกี่ยวขาตาม %d | เกี่ยวทั้งคู่ %d%s%s%s",
                     g_set_n, sr[1], sr[2], sr[3], sr[4], (g_set_on ? " | มีชุดที่ยังไม่จบ" : ""), (g_t5_leg >= 0 ? " | ถือ T5 อยู่" : ""), (g_s2_leg >= 0 ? " | ถือ S2 อยู่" : ""));
   string tail = "";
   if(g_rp_skip_n > 0) tail += StringFormat(" | ⚠️ ข้ามช่วงที่ดึง tick ไม่ได้ %d ช่วง (ล่าสุด %s)", g_rp_skip_n, g_rp_skip_txt);
   s += StringFormat("\n   T2 %d ไม้ ($%+.2f) | T3 %d ไม้ ($%+.2f) | T4 %d ไม้ ($%+.2f) | T5 %d ไม้ ($%+.2f)%s",
                     cnt[2], usd_st[2], cnt[3], usd_st[3], cnt[4], usd_st[4], cnt[5], usd_st[5], tail);
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
   if(InpReplayCSV && g_rp_csv_rows >= 0)
      s += StringFormat("\n   📄 CSV: MQL5\\Files\\%s (%d ไม้)", ReplayCSVName(), g_rp_csv_rows);
   if(InpReplayCSV && g_set_csv_rows >= 0)
      s += StringFormat(" | %s (%d ชุด)", ReplaySetsCSVName(), g_set_csv_rows);
   return s;
}


const int  RP_SKIP_SEC   = 30;       // ดึง tick ช่วงหนึ่งไม่สำเร็จนานเกินนี้ → ข้ามช่วงนั้น
const long RP_BUDGET_US  = 150000;   // เล่นซ้ำได้ไม่เกินกี่ไมโครวินาทีต่อรอบ (ไม่บล็อกงานเทรดนาน)

string ReplayCSVName() { return "7LCEA_Replay_" + _Symbol + ".csv"; }

string ReplayReasonCode(int r) {
   switch(r) {
      case RX_TIME: return "TIME";
      case RX_SL:   return "SL";
      case RX_WEEK: return "WEEKCLOSE";
      case RX_PEND: return "PENDING";
      case RX_EXP:  return "EXPIRED";
      case RX_LOCK:   return "LOCK";
      case RX_FLIP:   return "BOTH_CUT";
      case RX_TRAIL:  return "TRAIL";
      case RX_TP:     return "TP";
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

// เขียนไม้จำลองที่ปิดแล้ว + ค่าตอนสัญญาณ + ระยะกำไรระหว่างถือ (เขียนใหม่ทั้งไฟล์เมื่อมีไม้ปิดเพิ่ม)
void ReplayWriteCSV(int done) {
   string fn = ReplayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "set_id,order_kind,signal_time,signal_side,order_price,sl_mode," +
                      "time_in,side,tier,max_tier,bar_seq,lot,price_in,sl_peak,sl_init_pts,z_reg,z_sma,ext_zreg,ext_zsma,z_float," +
                      "spd_any_t2_sec,spd_any_t3_sec,spd_any_t4_sec,spd_any_from_open,spd_any_rate_t2,k2,k2_max," +
                      "zreg_bar_open,zreg_bar_high,zreg_bar_low,zsma_bar_open,zsma_bar_high,zsma_bar_low," +
                      "time_out,exit,hold_sec,pnl_pts,usd,profit_min_pts,profit_max_pts,profit_avg_pts,profit_max_sec,lock_on_sec,lock_level,long_mode,both_filled,tp_price\r\n");
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(!RDone(g_rt[i].reason)) continue;
      string ln = StringFormat("%d,%s,%s,%s,%s,%s,", g_rt[i].set_id, (g_rt[i].kind == 0 ? "COUNTER" : (g_rt[i].kind == 1 ? "TREND" : (g_rt[i].kind == 2 ? "T5_MARKET" : "S2_MARKET"))),
                               TimeToString((datetime)(g_rt[i].msc_sig / 1000), TIME_DATE|TIME_SECONDS), (g_rt[i].sig_dir == -1 ? "UP" : "DOWN"),
                               DoubleToString(g_rt[i].p_order, _Digits), SLModeCode(g_rt[i].sl_mode));
      ln += StringFormat("%s,%s,%d,%d,%d,%.2f,%s,%s,%.0f,%.3f,%.3f,%.3f,%.3f,",
                               TimeToString((datetime)(g_rt[i].msc_in / 1000), TIME_DATE|TIME_SECONDS), (g_rt[i].dir == -1 ? "SELL" : "BUY"),
                               g_rt[i].stage, g_rt[i].max_tier, g_rt[i].bar_seq, g_rt[i].lot, DoubleToString(g_rt[i].p_in, _Digits),
                               DoubleToString(g_rt[i].peak, _Digits),
                               PriceToPts(MathAbs(g_rt[i].sl0 - g_rt[i].p_in)), g_rt[i].zr, g_rt[i].zs, g_rt[i].ext_r, g_rt[i].ext_s);
      ln += StringFormat("%.3f,", g_rt[i].z_float);
      bool so = g_rt[i].ss_ok;
      ln += CsvSpeedAny(so, g_rt[i].ss.sp) + CsvNum(so, g_rt[i].ss.k2, 0) + "," + CsvNum(so, g_rt[i].ss.k2_max, 0) + ",";
      ln += StringFormat("%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,", g_rt[i].zb[0], g_rt[i].zb[1], g_rt[i].zb[2], g_rt[i].zb[3], g_rt[i].zb[4], g_rt[i].zb[5]);
      ln += StringFormat("%s,%s,%d,%.0f,%.2f,%.0f,%.0f,%.0f,%d,%s,%d,%d,%d,%s\r\n",
                         TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS), ReplayReasonCode(g_rt[i].reason),
                         (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000), g_rt[i].pnl, g_rt[i].usd,
                         PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ProfitAvgPts(i), (int)((g_rt[i].mfe_msc - g_rt[i].msc_in) / 1000),
                         (g_rt[i].lock_on_msc > 0 ? IntegerToString((g_rt[i].lock_on_msc - g_rt[i].msc_in) / 1000) : ""), g_rt[i].lock_lv,
                         g_rt[i].mode, (g_rt[i].both ? 1 : 0), (g_rt[i].tp > 0.0 ? DoubleToString(g_rt[i].tp, _Digits) : ""));
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_rp_csv_rows < 0) PrintFormat("📄 บันทึกไม้จำลอง %d ไม้ + ค่าตอนสัญญาณ ลง MQL5\\Files\\%s (อัปเดตเมื่อมีไม้ปิดเพิ่ม)", done, fn);
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
                      "spd_any_t2_sec,k2," +
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
      ln += CsvNum(so && g_rt[c].ss.sp.sec[0] >= 0, g_rt[c].ss.sp.sec[0], 0) + "," + CsvNum(so, g_rt[c].ss.k2, 0) + ",";
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

   ulong t0 = GetMicrosecondCount();
   if(g_rp_buf_i >= g_rp_buf_n) {   // บัฟเฟอร์หมด → โหลดช่วงถัดไป (ครั้งแรกทีละ 12 ชม.)
      long chunk = g_rp_caught ? (now_msc - g_rp_cursor) : (long)DAY_SEC * 500;
      long to    = MathMin(g_rp_cursor + chunk, now_msc);
      if(to >= g_rp_cursor) {
         int got = CopyTicksRange(_Symbol, g_rp_buf, COPY_TICKS_INFO, (ulong)g_rp_cursor, (ulong)to);
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
         g_rp_retry  = 0;
         g_rp_buf_n  = got;
         g_rp_buf_i  = 0;
         g_rp_buf_to = to;
         if(got > 0)            g_rp_cursor = (long)g_rp_buf[got - 1].time_msc + 1;
         else if(!g_rp_caught)  g_rp_cursor = to + 1;
      }
   }
   while(g_rp_buf_i < g_rp_buf_n) {   // เล่น tick ในบัฟเฟอร์ตามงบเวลา (ที่เหลือเล่นรอบถัดไป)
      ReplayTick(g_rp_buf[g_rp_buf_i++]);
      if((g_rp_buf_i & 255) == 0 && GetMicrosecondCount() - t0 > (ulong)RP_BUDGET_US) break;
   }
   if(!g_rp_caught && g_rp_buf_i >= g_rp_buf_n && g_rp_buf_to >= now_msc - 2000) {
      g_rp_caught = true;
      g_barz_bar  = 0;   // เล่นซ้ำครบ → วาดป้าย Z บนแท่งใหม่ทั้งชุด (มีความเร็ว Z ของแท่งย้อนหลังแล้ว)
   }
   if(g_rp_caught) ReplayTimeEvents(now_msc);   // เวลาผ่านไปโดยไม่มี tick (ปิดสัปดาห์ / ยิงหลังครบเวลาเฝ้า)

   g_rp_status = g_rp_caught
                 ? StringFormat("✅ ครบแล้ว + เดินต่อแบบสด (%I64d ticks)", g_rp_ticks)
                 : StringFormat("⏳ กำลังเล่นซ้ำ ถึง %s (%I64d ticks)", TimeToString((datetime)(g_rp_msc / 1000), TIME_DATE|TIME_MINUTES), g_rp_ticks);
   ReplayDraw();
   if(InpReplayCSV && g_rp_caught) {
      int done = 0;
      for(int i = 0; i < ArraySize(g_rt); i++) if(RDone(g_rt[i].reason)) done++;
      if(done != g_rp_csv_rows) ReplayWriteCSV(done);
      int sets = 0;
      for(int i = 0; i < ArraySize(g_rt); i++) if(g_rt[i].kind == 0 && SetResult(i) > 0) sets++;
      if(sets != g_set_csv_rows) ReplayWriteSetsCSV(sets);
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
   long now_msc = NowMsc();
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
                   StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s) | T2 ลอย > %.1f + ตัวใด > %.2f / T3 ตัวใด > %.2f / T4 ตัวใด > %.2f / T5 แตะ > %.2f",
                                g_z_reg, DoubleToString(g_center, _Digits), g_z_sma, DoubleToString(g_sma_mean, _Digits),
                                InpFloatMin, InpT2_Z, InpT3_Z, InpT4_Z, InpT5_Z));

   g_live_z_text = text;
   g_live_z_y    = y;
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
   string   hold = SetActive() ? " | ⏸️ ชุด T2-T4 ยังไม่จบ (ชุดนี้ยังไม่หาสัญญาณใหม่)"
                 : (SetBarUsed(g_set_bar, g_zbar_time) ? " | ⏸️ แท่งนี้วางชุด T2-T4 ไปแล้ว (1 ชุด/แท่ง)" : "");
   if(w.active) {
      double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
      if(left < 0.0) left = 0.0;
      string need = (w.tier == 4) ? StringFormat("Z ตัวใด > %s%.2f, รอ %d วิ", sg, InpT4_Z, InpT4_Sec)
                  : (w.tier == 3) ? StringFormat("Z ตัวใด > %s%.2f, รอ %d วิ", sg, InpT3_Z, InpT3_Sec)
                  : StringFormat("ลอย > %.1f + Z ตัวใด > %s%.2f, รอ %d วิ", InpFloatMin, sg, InpT2_Z, InpT2_Sec);
      double dist = PtsToPrice(InpStopDist_Pts);
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      return StringFormat("👀 เฝ้า %s (%s, Lot %.2f) | สุดขั้ว R %+.2f / S %+.2f | ยอดอ้างอิง %s | ถ้าวางตอนนี้: สวน %s @ %s (SL %s) / ตาม %s @ %s (SL คงที่ %.0f) | ไม่มียอดใหม่ (≥ %.0f จุด) มา %.1f วิ → วางในอีก %.1f วิ%s",
                          StageTag(w.tier), need, TierLot(w.tier), w.ext_r, w.ext_s, DoubleToString(w.ext_px, _Digits),
                          (dir == -1 ? "SELL STOP" : "BUY STOP"), DoubleToString(dir == -1 ? bid - dist : ask + dist, _Digits),
                          DoubleToString(SLPrice(dir, g_bar0_hi, g_bar0_lo), _Digits),
                          (dir == -1 ? "BUY STOP" : "SELL STOP"), DoubleToString(dir == -1 ? ask + dist : bid - dist, _Digits),
                          InpTrendSL_Pts, InpNoNewExt_Pts, (double)(now_msc - w.last_new) / 1000.0, left, hold);
   }
   string t2  = !g_en[2] ? "T2 ปิดปุ่ม"
              : (InpFloatFilter && zf <= InpFloatMin) ? StringFormat("T2 ปิด (ลอย %+.2f ≤ %.2f)", zf, InpFloatMin)
              : StringFormat("T2 Z ตัวใด > %s%.2f", sg, InpT2_Z);
   string t34 = StringFormat("%s / %s", (g_en[3] ? StringFormat("T3 Z ตัวใด > %s%.2f", sg, InpT3_Z) : "T3 ปิดปุ่ม"),
                             (g_en[4] ? StringFormat("T4 > %s%.2f", sg, InpT4_Z) : "T4 ปิดปุ่ม"));
   return StringFormat("✅ รอ %s | %s (Z_float %+.2f)%s", t2, t34, zf, hold);
}

// ชุด T5 บน Dashboard
string T5Text(datetime now) {
   if(!g_en[5]) return "⛔ ปิดปุ่ม";
   string s = StringFormat("แตะ |Z| > %.1f ในแท่ง → เปิดแท่งใหม่ Market สวน (Lot %.2f, SL %.0f)", InpT5_Z, TierLot(5), InpT5_SL_Pts);
   if(g_t5_pend_dir != 0)
      s += StringFormat(" | 🔔 รอเปิด %s (แท่งก่อนแตะ %+.2f, ลองได้อีก %d วิ)", (g_t5_pend_dir == -1 ? "SELL" : "BUY"), g_t5_pend_z,
                        (int)MathMax((long)0, (long)(g_t5_pend_until - now)));
   if(g_t5_cur_dir != 0) s += StringFormat(" | แท่งนี้แตะแล้ว %+.2f → เปิด %s แท่งถัดไป", g_t5_cur_z, (g_t5_cur_dir == -1 ? "SELL" : "BUY"));
   if(SysPositions(2) > 0) s += " | ถือ T5 อยู่ (ไม่เปิดซ้อน)";
   return s;
}

// ชุด S2 บน Dashboard
string S2Text(long now_msc) {
   if(!g_en[6]) return "⛔ ปิดปุ่ม";
   if(!g_s2.ok) return "รอข้อมูลแท่ง";
   string s = StringFormat("แท่งก่อน Z ที่ High %+.2f / Low %+.2f (เกณฑ์ %.1f) | ", g_s2.p_zhi, g_s2.p_zlo, InpS2_PrevZ);
   if(g_s2.done) return s + "เปิด / ทิ้งแล้วในแท่งนี้";
   string st = "";
   for(int k = 0; k < 2; k++) {
      if(!S2Armed(g_s2, k)) continue;
      string side = (k == 0) ? "SELL ไส้บน" : "BUY ไส้ล่าง";
      if(g_s2.cancel[k])  st += side + " ยกเลิก (ทะลุยอดแท่งก่อน) ";
      else if(g_s2.sb[k]) st += StringFormat("%s สแตนบาย ยิงในอีก %.1f วิ ", side, MathMax(0.0, (S2Deadline(g_s2, k) - now_msc) / 1000.0));
      else                st += StringFormat("%s รอราคาเข้าไส้ %s ", side, DoubleToString((k == 0) ? MathMax(g_s2.p_open, g_s2.p_close) : MathMin(g_s2.p_open, g_s2.p_close), _Digits));
   }
   if(st == "") st = "แท่งก่อนไม่ถึงเกณฑ์";
   if(SysPositions(3) > 0) st += "| ถือ S2 อยู่ (ไม่เปิดซ้อน)";
   return s + st;
}

string PositionLines(double bid, double ask, datetime now) {
   string out = "";
   for(int i = OrdersTotal() - 1; i >= 0; i--) {   // ออเดอร์รอของชุด
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder()) continue;
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      long     left  = (long)(setup + (datetime)(InpStopExpire_Min * 60) - now);
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
      string st = "";
      int    sys = SysOfComment(PositionGetString(POSITION_COMMENT)), mode = 0;
      for(int k = ArraySize(g_pm) - 1; k >= 0; k--) {
         if(g_pm[k].tk != ticket) continue;
         mode = g_pm[k].mode;
         st = StringFormat(" | สูงสุด %+.0f", PriceToPts(g_pm[k].mfe));
         if(sys == 3) break;
         if(mode == 1) st += " | 🏃 วิ่งยาว";
         if(g_pm[k].both) st += " | 🔁 ขาที่ 2";
         double lk = (sl > 0.0) ? (is_buy ? PriceToPts(sl - open) : PriceToPts(open - sl)) : 0.0;
         if(g_pm[k].lock_lv == 4)    st += StringFormat(" | 🛡️ ไล่จี้ ล็อก %+.0f", lk);
         else if(g_pm[k].lock_lv > 0) st += StringFormat(" | 🛡️ เกราะขั้น %d ล็อก %+.0f", g_pm[k].lock_lv, lk);
         else st += StringFormat(" | เกราะเมื่อกำไรถึง %.0f", InpLock1_Trig_Pts);
         break;
      }
      string ex = (sys == 3) ? StringFormat("TP %s", DoubleToString(PositionGetDouble(POSITION_TP), _Digits))
                             : "ตัดจบในอีก " + FormatDuration(MathMax(0, (long)(ExitTimeOfN(opened, (mode == 1) ? InpLongExitBars : InpExitBars) - now)));
      out += StringFormat("\n  #%I64u %s %s %.2f @ %s | กำไร %+.0f จุด | SL %s | ถือ %s | %s%s",
                          ticket, KindFromComment(PositionGetString(POSITION_COMMENT)), (is_buy ? "BUY" : "SELL"), PositionGetDouble(POSITION_VOLUME),
                          DoubleToString(open, _Digits), prof, DoubleToString(sl, _Digits), FormatDuration((long)(now - opened)), ex, st);
   }
   return out;
}

// สถิติ tick ของแท่งปัจจุบันแบบอ่านง่าย (log ตอนวางชุดออเดอร์)
string LiveStatText(int side) {
   BarSpeed bs;
   if(!SpeedOf(CurrentZBarTime(), bs)) return "ยังไม่มีข้อมูล tick";
   SideStat st;
   st = bs.sd[side];
   double rate = SpeedRate(st.sp, 0);
   return StringFormat("เร็ว (จาก Z %.1f) %s%s · K2 %d · Z สูงสุด %+.2f",
                       InpSpeedFromZ, SpeedLong(st.sp), (rate >= 0.0 ? StringFormat(" (%.2f Z/วิ)", rate) : ""), st.k2,
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

   long   now_msc = NowMsc();
   string msg = StringFormat("=== 📊 7-Lines Counter EA v14.91 (%s T2 ลอย>%.2f Z>%.1f %d วิ | %s T3 >%.1f %d วิ | %s T4 >%.1f %d วิ | ยอดใหม่ ≥%.0f | Stop ±%.0f: สวน SL ยอด±%.0f / ตาม SL %.0f | %s T5 แตะ>%.1f → แท่งใหม่ SL %.0f | %s S2 แท่งก่อน>%.1f ไส้ %d วิ SL ยอด (%.0f–%.0f) TP %.1fR | ตัดจบ %d แท่ง | เกราะ %.0f→+%.0f / %.0f→+%.0f / %.0f→+%.0f | วิ่งยาว: ไล่จี้ %.0f เมื่อ ≥%.0f ตัดจบ %d แท่ง) ===\n",
                             (g_en[2] ? "✅" : "⛔"), InpFloatMin, InpT2_Z, InpT2_Sec, (g_en[3] ? "✅" : "⛔"), InpT3_Z, InpT3_Sec,
                             (g_en[4] ? "✅" : "⛔"), InpT4_Z, InpT4_Sec, InpNoNewExt_Pts, InpStopDist_Pts, InpSLPeak_Pts, InpTrendSL_Pts,
                             (g_en[5] ? "✅" : "⛔"), InpT5_Z, InpT5_SL_Pts, (g_en[6] ? "✅" : "⛔"), InpS2_PrevZ, InpS2_NoNewSec, InpS2_MinSL_Pts, InpS2_MaxSL_Pts, InpS2_RR,
                             InpExitBars, InpLock1_Trig_Pts, InpLock1_Pts, InpLock2_Trig_Pts, InpLock2_Pts, InpLock3_Trig_Pts, InpLock3_Pts,
                             InpLongTrail_Pts, InpLongTrailStart_Pts, InpLongExitBars);
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   if(news_str != "") msg += "ข่าว : " + news_str + "\n";
   msg += "SELL : " + WatchText(g_wsell, true,  now_msc) + "\n";
   msg += "BUY  : " + WatchText(g_wbuy,  false, now_msc) + "\n";
   msg += "T5   : " + T5Text(now) + "\n";
   msg += "S2   : " + S2Text(now_msc) + "\n";
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts);
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
// 🔘 ปุ่มเปิด/ปิด T2-T5 / S2 + ป้ายไม้ไม่ซ้อนกัน
//====================================================================
// เวลาภายในแท่ง (TF ของ Z) เช่น "น.07:32" = นาทีที่ 7 วินาทีที่ 32 นับจากเปิดแท่ง
string BarMinText(datetime t) {
   long sec = (long)t - (long)BarStartOf(t);
   return StringFormat("น.%02d:%02d", (int)(sec / 60), (int)(sec % 60));
}

const string BTN_PREFIX = "7LCEA_BTN_T";
const string PANEL_PREFIX = "7LCEA_PN_";
const int    LAYOUT_MAX_SHIFT = 3;   // ป้ายบนแท่งเลื่อนออกจากแท่งได้ไม่เกินกี่แถว (เกิน = ซ่อน)

// ชื่อปุ่ม: 2-5 = T2-T5, 6 = S2, 7 = 1 ชุด/แท่ง
string BtnTag(int t) { return (t == 7) ? "1/แท่ง" : ((t == 6) ? "S2" : StageTag(t)); }

string TierGVName(int tier) { return StringFormat("7LCEA_%s_%I64d_T%d", _Symbol, InpMagic, tier); }

// ค่าเริ่มต้นของปุ่ม: แก้ input = ใช้ input / เปลี่ยน TF, คอมไพล์ใหม่, สลับบัญชี = ใช้สถานะปุ่มล่าสุด
void TierEnableInit() {
   int  r       = UninitializeReason();
   bool restore = (r == REASON_CHARTCHANGE || r == REASON_RECOMPILE || r == REASON_ACCOUNT);
   ArrayInitialize(g_en, false);
   g_en[2] = InpEnableT2; g_en[3] = InpEnableT3; g_en[4] = InpEnableT4; g_en[5] = InpEnableT5; g_en[6] = InpEnableS2; g_en[7] = InpOneSetPerBar;
   for(int t = 2; t <= 7; t++) {
      if(restore && GlobalVariableCheck(TierGVName(t))) g_en[t] = (GlobalVariableGet(TierGVName(t)) > 0.5);
      GlobalVariableSet(TierGVName(t), g_en[t] ? 1.0 : 0.0);
   }
}

void DrawTierButtons() {
   if(!g_draw) return;
   for(int t = 2; t <= 7; t++) {
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
      ObjectSetString(0,  nm, OBJPROP_TEXT, BtnTag(t) + (g_en[t] ? " ON" : " OFF"));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, g_en[t] ? clrSeaGreen : clrDimGray);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP, StringFormat("คลิกเพื่อ%s %s (Tick Replay จะเล่นซ้ำใหม่ตามระบบที่เปิด)", (g_en[t] ? "ปิด" : "เปิด"), BtnTag(t)));
   }
}

// สลับระดับ → เก็บสถานะ, ล้างการเฝ้า, เล่นซ้ำ Tick Replay ใหม่ตามระดับที่เปิด
void ToggleTier(int tier) {
   if(tier < 2 || tier > 7) return;
   g_en[tier] = !g_en[tier];
   GlobalVariableSet(TierGVName(tier), g_en[tier] ? 1.0 : 0.0);
   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   ObjectsDeleteAll(0, OBJ_PREFIX + "RP_");
   ReplayReset();
   g_lay_sig     = "";
   g_barz_bar    = 0;
   g_last_status = StringFormat("%s %s (ปุ่ม) — Tick Replay เริ่มเล่นซ้ำใหม่", BtnTag(tier), (g_en[tier] ? "เปิด" : "ปิด"));
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
//   2) ป้ายบนแท่ง: กลุ่มละ 1 แท่ง 1 ฝั่ง (แถว Z ติดแท่ง, แถวเร็ว / K2 ด้านนอก) จัดแท่งใหม่ก่อน, เลื่อนออกจากแท่งได้ไม่เกิน LAYOUT_MAX_SHIFT แถว
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

   // 4) ป้ายบนแท่ง (TF ของ Z) ในช่วงที่มองเห็น — กลุ่มละ 2 ป้าย (แถว Z ติดแท่ง, แถวเร็ว / K2 ด้านนอก)
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
   string   gi[];   // ชื่อป้ายของกลุ่ม g = gi[g * 2 + m]
   for(int q = 0; q < got; q++) {
      string ts = IntegerToString((long)zb[q].time);
      bool   live = (q == got - 1 && zb[q].time == CurrentZBarTime());
      double hi = (live && g_bar0_hi > 0.0) ? g_bar0_hi : zb[q].high;
      double lo = (live && g_bar0_lo > 0.0) ? g_bar0_lo : zb[q].low;
      for(int u = 0; u < 2; u++) {   // u = 0 เหนือแท่ง (SELL) / 1 ใต้แท่ง (BUY)
         string i0 = OBJ_PREFIX + (u == 0 ? "ZL_S_" : "ZL_B_") + ts;
         if(ObjectFind(0, i0) < 0) continue;
         ArrayResize(gt, ng + 1); ArrayResize(gup, ng + 1); ArrayResize(gbase, ng + 1); ArrayResize(gkey, ng + 1); ArrayResize(gi, (ng + 1) * 2);
         gt[ng] = zb[q].time; gup[ng] = (u == 0); gbase[ng] = (u == 0) ? hi + off : lo - off;
         gkey[ng] = (long)zb[q].time;   // แท่งใหม่ก่อน
         gi[ng * 2] = i0; gi[ng * 2 + 1] = OBJ_PREFIX + (u == 0 ? "ZM_S_" : "ZM_B_") + ts;
         ng++;
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
         for(int m = 0; m < 2; m++) { string s0 = gi[b * 2 + m]; gi[b * 2 + m] = gi[(b - 1) * 2 + m]; gi[(b - 1) * 2 + m] = s0; }
         b--;
      }
   }
   for(int g = 0; g < ng; g++) {
      int x = 0, y = 0;
      bool onscreen = ChartTimePriceToXY(0, 0, gt[g], gbase[g], x, y);
      double cursor = y;
      bool   hide   = !onscreen;
      for(int m = 0; m < 2; m++) {
         string nm2 = gi[g * 2 + m];
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
// 🔎 กล่องรายละเอียดแท่ง (มุมซ้ายล่าง เหนือปุ่ม T2-T5): ชี้เมาส์ที่แท่ง → ค่าทั้งหมดของแท่งนั้น
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
   int got = CopyRates(_Symbol, InpZ_Timeframe, bar, n + 1, r);
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
      double rate = SpeedRate(st.sp, 0);
      PanelAdd(L, C, StringFormat("เร็ว (Z ตัวใดก็ได้ จาก %.1f)    %s%s%s", InpSpeedFromZ, SpeedLong(st.sp),
                                  (rate >= 0.0 ? StringFormat("    อัตรา %.3f Z/วิ", rate) : ""), (bs.fresh ? "" : "    (เริ่มนับกลางแท่ง)")), InpClrPanelText);
      PanelAdd(L, C, StringFormat("K2 (ทำยอดใหม่ใน %d วิ ก่อนยอดล่าสุด)    %d ครั้ง    สูงสุดในแท่ง %d", InpK2_Window_Sec, st.k2, st.k2_max), InpClrPanelText);
   }
   else PanelAdd(L, C, "เร็ว / K2:  ไม่มีข้อมูล tick (เก่ากว่าช่วง Tick Replay)", InpClrBarZOther);
   PanelAdd(L, C, StringFormat("ป้ายแถว 2:  เร็ว = วิ จาก Z %.1f ถึง %.1f · K2 · * = นับจากเปิดแท่ง", InpSpeedFromZ, InpT2_Z), InpClrBarZOther);
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
   if(InpT2_Z <= 0.0 || InpT3_Z < InpT2_Z || InpT4_Z < InpT3_Z || InpT5_Z < InpT4_Z || InpT4_Sec < 0 || InpT5_RetrySec < 0 || InpT5_SL_Pts <= 0.0 ||
      InpT2_Sec < 0 || InpT3_Sec < 0 || InpNoNewExt_Pts < 0.0 || InpTierLotStep < 0.0 || InpSpeedFromZ < 0.0 ||
      InpS2_NoNewSec < 0 || InpS2_MinSL_Pts < 0.0 || InpS2_MaxSL_Pts < 0.0 || InpS2_RR <= 0.0 || InpS2_Lot <= 0.0) {
      Print("❌ ค่า Z ระดับวิกฤต (ต้อง T2 ≤ T3 ≤ T4 ≤ T5) / เวลาเฝ้า / ยอดใหม่ / T5 / S2 / Lot ต่อระดับ / จุดเริ่มจับความเร็ว Z ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLot <= 0.0) { Print("❌ Lot ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpStopDist_Pts <= 0.0 || InpSLPeak_Pts < 0.0 || InpExitBars < 0 || InpCounterMaxSL_Pts < 0.0 || InpTrendSL_Pts <= 0.0 ||
      InpStopExpire_Min < 1 || InpLock1_Trig_Pts < 0.0 || InpLock2_Trig_Pts < 0.0 || InpLock3_Trig_Pts < 0.0 ||
      (InpLock1_Trig_Pts > 0.0 && InpLock1_Pts >= InpLock1_Trig_Pts) || (InpLock2_Trig_Pts > 0.0 && InpLock2_Pts >= InpLock2_Trig_Pts) ||
      (InpLock3_Trig_Pts > 0.0 && InpLock3_Pts >= InpLock3_Trig_Pts) ||
      InpLongTrailStart_Pts < 0.0 || InpLongTrail_Pts <= 0.0 || InpLongExitBars < 0 || InpTrailStep_Pts < 0.0) {
      Print("❌ ระยะ Stop / SL / เพดาน SL / SL ตามน้ำ / โหมดวิ่งยาว / อายุ Stop / เกราะ (ระยะล็อกต้องน้อยกว่ากำไรที่สั่งขยับ) / จำนวนแท่งตัดจบ ไม่ถูกต้อง");
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
   g_barz_bar = 0;
   ArrayResize(g_zl_names, 0);
   ArrayResize(g_zl_times, 0);
   TrackerReset(g_trk_live);
   ArrayResize(g_spd_hist, 0);
   g_lbl_ver = 0; g_pn_bar = 0; g_pn_side = -1; g_pn_text = "";

   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   g_t5_cur_dir = 0; g_t5_cur_z = 0.0; g_t5_pend_dir = 0; g_t5_pend_z = 0.0; g_t5_pend_until = 0; g_t5_next_try = 0;
   S2Clear(g_s2);
   g_s2_next_try   = 0;
   g_set_bar       = 0;
   g_both_tk       = 0; g_both_sl = 0.0;
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
   ArrayResize(g_marks, 0);
   g_marks_bar = 0;
   g_newsviz_loaded = 0;
   ArrayResize(g_newsviz_names, 0);
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   g_last_comment   = "";
   g_live_z_text = ""; g_live_z_y = -1;
   g_del_retry = 0;
   g_heavy_ms  = 0;
   ArrayResize(g_pm, 0);

   RefreshNews(ServerNow());
   TierEnableInit();
   g_lay_sig = "";

   ObjectsDeleteAll(0, OBJ_PREFIX);
   LoadEntryMarksFromHistory();
   if(g_draw && InpShowBarPanel) ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   DrawTierButtons();

   EventSetMillisecondTimer(200);   // งานเทรด (เกราะ / ตัดจบ / หมดอายุ / ยิงเมื่อครบเวลา) ทุก 200 ms, งานแสดงผลทุก 1 วินาที
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
   g_tick_local    = GetTickCount();   // นาฬิกาเสริม: เวลา tick + เวลาที่ผ่านไปในเครื่อง
   if(!UpdateZ(tk.bid)) return;
   TrackTick(g_trk_live, g_z_reg, g_z_sma, tk.bid, g_last_tick_msc);   // สถิติ tick ของแท่ง (ตามเวลาของ tick)
   T5Touch(g_t5_cur_dir, g_t5_cur_z, g_z_reg, g_z_sma);               // T5: แตะ > T5 ในแท่ง
   S2Tick(g_s2, tk.bid, g_last_tick_msc);                              // S2: ไส้แท่งปิดล่าสุด

   // งานเทรดก่อน (ส่งคำสั่งให้เร็วที่สุด) → แสดงผลทีหลัง
   datetime now = ServerNow();
   int      ts  = GetTimeState(now);
   if(ts == TS_CLOSING) CloseAllPositions();
   else {
      if(ts != TS_CLOSED) ManageOrders(now, ts, g_last_tick_msc);   // ตัดจบ / เกราะ / ยกเลิกออเดอร์รอที่หมดอายุ
      LiveSignalStep(g_last_tick_msc, ts, tk.bid, tk.ask, true);
      LiveT5Step(now, ts, tk.bid, tk.ask);
      LiveS2Step(now, ts, tk.bid, tk.ask, g_last_tick_msc);
   }
   UpdateLiveZLabel(tk.bid);
}

void OnTimer() {
   datetime now     = ServerNow();
   long     now_msc = NowMsc();
   int      ts      = GetTimeState(now);

   // 1. งานเทรดทุก 200 ms (แม้ไม่มี Tick เข้า): บังคับปิดก่อนตลาดปิดสัปดาห์ / ตัดจบ / เกราะ / หมดอายุ / ยิงเมื่อครบเวลาเฝ้า
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManageOrders(now, ts, now_msc);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   zok = (bid > 0.0 && ask > 0.0 && UpdateZ(bid));
   if(zok && ts != TS_CLOSING) {
      LiveSignalStep(now_msc, ts, bid, ask, false);
      LiveT5Step(now, ts, bid, ask);
      LiveS2Step(now, ts, bid, ask, now_msc);
   }

   // 2. แสดงผลทุก 1 วินาที — ช่วงร้อน (กำลังเฝ้าสัญญาณ) ข้ามงานหนัก (Replay, จัดป้าย, กล่องรายละเอียด, ข่าว)
   if(!g_draw || GetTickCount() - g_heavy_ms < 1000) return;
   g_heavy_ms = GetTickCount();
   bool hot = LiveHot();
   UpdateBarZLabels();
   if(!hot) {
      RefreshNews(now);
      UpdateEntryMarks();
      ReplayStep();
      LayoutLabels();
      DrawBarPanel(false);
      LoadNewsHistory();
   }
   if(bid > 0.0) UpdateLiveZLabel(bid);
   UpdateDashboard(ts, now);
   ChartRedraw(0);   // ให้วัตถุแสดงผลแม้ช่วงที่ไม่มี Tick เข้า
}

// คลิกปุ่ม T2-T5 → เปิด/ปิดระดับ | ชี้เมาส์ → กล่องรายละเอียดแท่ง | เลื่อน/ซูม/ย่อขยายกราฟ → จัดตำแหน่งป้ายใหม่ทันที
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
   // ดีลเปิด S2 → นับว่าเปิดแล้วในแท่งนี้ (กันเปิดซ้ำแม้ผลส่งคำสั่งมาช้า)
   if(IsOurDeal(trans.deal, DEAL_ENTRY_IN) && SysOfComment(HistoryDealGetString(trans.deal, DEAL_COMMENT)) == 3 &&
      (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME) >= g_s2.bar) g_s2.done = true;
}
//+------------------------------------------------------------------+
