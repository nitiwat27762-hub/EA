# EA
indicator EA XAUUSD

## Indicators

| ไฟล์ | เวอร์ชัน | รายละเอียด |
|---|---|---|
| `Indicators/Seven_Lines_Exhaustion_Ind.mq5` | 8.82 | 7-Lines Exhaustion + Z-Score (MQL5) |

### v8.82
- สัญญาณย้อนหลังไม่ Repaint: จุดเริ่มจำลองถูกล็อก และสถานะถูกเดินต่อทีละแท่ง
- แท่งปัจจุบันแสดงสัญญาณแบบพรีวิว "(สด)" ทุก Tick พร้อมตัวจับเวลา No New High/Low — ยืนยันถาวรเมื่อปิดแท่ง
- ลบป้ายข้อความค้าง, คำนวณเส้นเฉพาะแท่งที่เปลี่ยน, SL จำลองขยับทางเดียว, ตรวจ Input

ติดตั้ง: คัดลอกไฟล์ไปที่ `MQL5/Indicators/` แล้วคอมไพล์ใน MetaEditor
