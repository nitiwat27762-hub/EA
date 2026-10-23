//+------------------------------------------------------------------+
//|                                     Seven_Lines_Context_Ind.mq5  |
//|     Z_reg / Z_SMA แบบเดียวกับ Counter EA + ตารางถอยจากยอด (no new Z)  |
//+------------------------------------------------------------------+
//
// 📐 Z (สูตรเดียวกับ Counter EA, หน้าต่าง 20 แท่ง = แท่งปิด 19 แท่งก่อนหน้า + ราคาที่วัด)
//  • Z_reg = (ราคา − เส้นถดถอย) ÷ max(SD ส่วนเหลือ, 0.5 × SD ของส่วนต่างต่อแท่ง)
//  • Z_SMA = (ราคา − SMA20) ÷ SD20
//
// 🖼️ แสดงผลแบบเดียวกับ Counter EA
//  • ป้าย "R+2.31 | S+2.05" บนแท่งที่ Z ที่ High (SELL) / Low (BUY) เกินเกณฑ์ T2 (สี = เข้าระดับ, เทา = ไม่ครบ)
//  • ป้าย Z_float "F+1.23" = (ราคาเปิด − SMA ตอนเปิดแท่ง) ÷ SD (แท่งปัจจุบันแสดงเสมอ)
//  • เส้นแนวนอนระดับ Z (เส้นถดถอย / SMA20 ± เกณฑ์ T2) + ป้าย Z สดที่ขอบขวา
//
// 📊 ตารางถอยจากยอด (มุมขวาล่าง, ปุ่มเลือกระดับ Z) — ใช้หาเกณฑ์ "no new Z" แบบระยะ แทน/เสริมแบบนับเวลา
//  • เส้นทางราคาในแท่ง = แท่ง M1 (แท่งเขียว: Low ก่อน High, แท่งแดง: High ก่อน Low)
//  • เหตุการณ์ = ในแท่งของกราฟ Z ตัวใดตัวหนึ่งที่ High ของแท่ง M1 (SELL) / Low (BUY) เกินระดับ → ติดตามยอด = High สูงสุดของแท่ง
//  • ตาราง 1: ราคาถอยจากยอด ≥ ΔZ (σ = SD20 ตอนแตะยอด) ครั้งแรก → เข้าที่ ยอด − ΔZ·σ
//    ตาราง 2: ไม่มียอดใหม่ครบ N นาที → เข้าที่ราคาปิดของแท่ง M1 นั้น
//  • ผล (อะไรเกิดก่อน ภายใน InpStudyMin นาทีหลังยอด): พุ่งต่อ = ทะลุยอด + 500 จุด (SL ของ EA) / สวน = ถอยถึง ยอด − 2σ / ไม่ชัด
//    ยอดใหม่ = ราคาทะลุยอดเดิม (เท่าไรก็ได้) ก่อนสวน, EV = กำไรเฉลี่ยต่อไม้ (จุด) ถ้าเข้าตามแถวนั้น
//  • ปุ่ม "💾 CSV" → MQL5/Files: 7LCTX_Study_<symbol>_<TF>.csv (สรุปทุกระดับ) + ..._trades.csv (ทุกไม้สมมติ) เปิดด้วย Excel ได้
//
#property copyright   "Commander's Quant System"
#property version     "3.11"
#property description "Z_reg / Z_SMA แบบเดียวกับ Counter EA + ตารางถอยจากยอด: ถอยแค่ไหนคือสวนกลับ / พุ่งต่อ"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

#property indicator_label1  "R เส้นถดถอย"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_DOT
#property indicator_label2  "R +T2"
#property indicator_type2   DRAW_LINE
#property indicator_style2  STYLE_DASH
#property indicator_label3  "R −T2"
#property indicator_type3   DRAW_LINE
#property indicator_style3  STYLE_DASH
#property indicator_label4  "S SMA20"
#property indicator_type4   DRAW_LINE
#property indicator_style4  STYLE_DOT
#property indicator_label5  "S +T2"
#property indicator_type5   DRAW_LINE
#property indicator_style5  STYLE_DASHDOT
#property indicator_label6  "S −T2"
#property indicator_type6   DRAW_LINE
#property indicator_style6  STYLE_DASHDOT

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== Z (สูตรเดียวกับ Counter EA) ==="
input int             InpZ_Period          = 20;          // จำนวนแท่งของหน้าต่าง
input double          InpSigmaFloorMult    = 0.50;        // พื้นตัวหาร Z_reg = ค่านี้ × SD ของส่วนต่างต่อแท่ง

input group "=== เกณฑ์ (เหมือน Counter EA) ==="
input double          InpT2_Z              = 2.50;        // T2 (ป้ายเริ่มแสดง, ต้องเกินทั้งคู่ถึงมีสี)
input double          InpT3_Z              = 3.00;        // T3 (ตัวใดตัวหนึ่ง)
input double          InpT4_Z              = 3.50;        // T4 (ตัวใดตัวหนึ่ง)
input double          InpFloatMin          = 1.80;        // T2 ต้องมี Z_float > ค่านี้ (T3/T4 ไม่ต้อง)
input double          InpT2EitherFloat     = 2.00;        // Z_float > ค่านี้ → T2 เกินตัวเดียวก็พอ

input group "=== ตารางถอยจากยอด (no new Z) ==="
input bool            InpShowStudy         = true;        // แสดงตาราง (มุมขวาล่าง)
input int             InpStudyDays         = 180;         // ย้อนหลังกี่วัน (ใช้ข้อมูล M1)
input double          InpStudyZ1           = 2.50;        // ระดับ Z ปุ่มที่ 1 (ตัวใดตัวหนึ่ง)
input double          InpStudyZ2           = 3.00;        // ระดับ Z ปุ่มที่ 2 (ค่าเริ่มต้น)
input double          InpStudyZ3           = 3.50;        // ระดับ Z ปุ่มที่ 3
input double          InpStudySL_Pts       = 500.0;       // พุ่งต่อ = ทะลุยอด + ระยะนี้ (จุด, = SL ของ EA)
input double          InpStudyTarget       = 2.0;         // สวน = ถอยจากยอดถึงกี่ σ
input int             InpStudyMin          = 60;          // รอผลกี่นาทีหลังยอด
input int             InpStudySkipFirstMin = 1;           // ไม่นับกี่นาทีแรกของแท่ง (เหมือน EA)
input int             InpStudySkipLastMin  = 2;           // ไม่นับกี่นาทีท้ายแท่ง (เหมือน EA)
input int             InpStudyMinN         = 30;          // แถวต้องมีอย่างน้อยกี่ไม้ถึงนับเป็นแถว EV ดีสุด

input group "=== แสดงผล (แบบเดียวกับ Counter EA) ==="
input bool            InpShowBarZ          = true;        // ป้าย Z บนแท่งที่ Z เกินเกณฑ์ T2
input int             InpBarZBars          = 2000;        // ป้ายย้อนหลังกี่แท่ง (0 = ทั้งหมด)
input int             InpBarZFontSize      = 8;           // ขนาดตัวอักษรป้าย
input double          InpBarZOffset_Pts    = 300.0;       // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowFloatMark     = true;        // ป้าย Z_float (ราคาเปิดลอยพ้น SMA)
input double          InpFloatMarkZ        = 1.00;        // ป้าย Z_float: แสดงเมื่อ |Z_float| > ค่านี้ (แท่งปัจจุบันแสดงเสมอ)
input bool            InpShowLevelLines    = true;        // เส้นแนวนอนระดับ Z ปัจจุบัน (เส้นถดถอย / SMA20 ± เกณฑ์ T2)
input bool            InpShowLiveZ         = true;        // ป้าย Z สดที่ขอบขวา
input int             InpLiveZFontSize     = 11;          // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;          // ระยะป้าย Z สดจากขอบขวา (พิกเซล)
input bool            InpShowHistLines     = false;       // เส้นย้อนหลัง: เส้นถดถอย / SMA20 ± เกณฑ์ T2 ทุกแท่ง

input group "=== สี (เหมือน Counter EA) ==="
input color           InpClrZCenter        = clrGold;           // เส้นกลาง Regression
input color           InpClrZSellLine      = clrOrangeRed;      // Regression ระดับ SELL
input color           InpClrZBuyLine       = clrAqua;           // Regression ระดับ BUY
input color           InpClrSmaCenter      = clrDarkKhaki;      // SMA20
input color           InpClrSmaSellLine    = clrLightSalmon;    // SMA20 ระดับ SELL
input color           InpClrSmaBuyLine     = clrPaleTurquoise;  // SMA20 ระดับ BUY
input color           InpClrBarZSell       = clrOrangeRed;      // ป้าย Z ฝั่ง SELL (เหนือแท่ง)
input color           InpClrBarZBuy        = clrDeepSkyBlue;    // ป้าย Z ฝั่ง BUY (ใต้แท่ง)
input color           InpClrBarZOther      = clrGray;           // ป้าย Z ที่ไม่เข้าระดับ
input color           InpClrFloatMark      = clrMediumPurple;   // ป้าย Z_float
input color           InpClrLiveSell       = clrOrangeRed;      // ป้าย Z สด: ถึงเกณฑ์ SELL
input color           InpClrLiveBuy        = clrDeepSkyBlue;    // ป้าย Z สด: ถึงเกณฑ์ BUY
input color           InpClrLiveNear       = clrGold;           // ป้าย Z สด: ใกล้เกณฑ์
input color           InpClrLiveNormal     = clrSilver;         // ป้าย Z สด: ปกติ
input color           InpClrTable          = clrSilver;         // ตาราง
input color           InpClrTableBest      = clrLimeGreen;      // ตาราง: แถวที่ EV ดีสุด

//====================================================================
// 🔒 INTERNAL
//====================================================================
const string PFX       = "7LCTX_";
const string BTN_PFX   = "7LCTX_BTN_";
const string GV_LVL    = "7LCTX_STUDY_LVL";
const string BTN_CSV   = "7LCTX_CSVBTN";
const double NEAR_ZONE = 0.5;
#define N_LVL 3
#define N_DEP 7
#define N_TIM 4
#define RES_SL 1
#define RES_RV 2
#define RES_UN 3

double bR[], bRp[], bRm[], bS[], bSp[], bSm[];

double   g_pmult = 1.0;
int      g_warm  = 0;

// ป้าย Z สด
string   g_live_text = "";
color    g_live_clr  = clrSilver;
double   g_live_bid  = 0.0;
string   g_live_tip  = "";

// ตารางถอยจากยอด
struct StudyStat {
   int    n;       // จำนวนไม้ที่ได้ผล
   int    nh;      // ทำยอดใหม่ก่อนสวน
   int    sl;      // พุ่งต่อ (ทะลุยอด + SL)
   int    rv;      // สวนถึงเป้า
   int    un;      // ไม่ชัด (ครบเวลา)
   double dist;    // ผลรวมระยะถอย (ตาราง 1: จุด, ตาราง 2: ΔZ)
   double ev;      // ผลรวมกำไร (จุด)
};
// ไม้สมมติแต่ละไม้ (สำหรับบันทึก CSV)
struct StudySample {
   int      lvl;      // ช่องระดับ (0..2)
   int      side;     // +1 = SELL, −1 = BUY
   int      kind;     // 0 = ถอย ≥ ΔZ, 1 = ไม่มียอดใหม่ครบ N นาที
   double   key;      // ΔZ หรือ นาที ของแถว
   datetime bar_t;    // เวลาแท่งของกราฟ
   datetime peak_t;   // เวลาแท่ง M1 ที่ทำยอด
   datetime entry_t;  // เวลาแท่ง M1 ที่เข้า
   datetime res_t;    // เวลาแท่ง M1 ที่ได้ผล
   double   z_peak;   // Z ตัวใหญ่สุดที่ยอด (ในทิศของฝั่ง)
   double   peak;     // ราคายอด (ราคาจริง)
   double   entry;    // ราคาเข้า (ราคาจริง)
   double   sig;      // SD20 ตอนแตะยอด (ราคา)
   int      res;      // RES_SL / RES_RV / RES_UN
   bool     nh;       // ทำยอดใหม่ก่อนสวน
   double   pnl;      // กำไร (ราคา)
};
StudySample g_smp[];
int         g_smp_n = 0;
StudyStat g_sd[N_LVL][N_DEP];
StudyStat g_st[N_LVL][N_TIM];
int       g_ev_n[N_LVL];
double    g_lvl[N_LVL];
double    g_dep_k[N_DEP] = {0.10, 0.20, 0.30, 0.50, 0.75, 1.00, 1.50};
int       g_tim_m[N_TIM] = {1, 2, 3, 5};
int       g_sel        = 1;          // ระดับที่แสดง (ปุ่ม)
MqlRates  g_m1[];
int       g_m1_n       = 0;
datetime  g_m1_from    = 0, g_m1_to = 0;
datetime  g_study_bar  = 0;          // แท่งของกราฟตอนคำนวณตารางล่าสุด
uint      g_study_retry = 0;
string    g_study_msg  = "";

//====================================================================
// 🧰 HELPERS
//====================================================================
double PtsToPrice(double pts) { return pts * g_pmult * _Point; }
double PriceToPts(double px)  { return px / (g_pmult * _Point); }

// Z แบบ EA: ราคาปิด c[i−n+1 .. i−1] + ราคา P
bool ZCore(const double &c[], int i, double P, double &fit, double &sig_r, double &mean, double &sd_s) {
   int n = InpZ_Period;
   if(i - n + 1 < 1) return false;
   double ref = c[i - 1];
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n - 1; k++) {
      int    idx = i - n + 1 + k;
      double y   = c[idx] - ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[idx] - c[idx - 1]; sd += d; sdd += d * d; }
   }
   double yP = P - ref;
   sy += yP; sxy += (n - 1) * yP; syy += yP * yP;
   double d0 = P - c[i - 1];
   sd += d0; sdd += d0 * d0;

   double nn  = (double)n;
   double sx  = nn * (nn - 1.0) / 2.0;
   double sxx = (nn - 1.0) * nn * (2.0 * nn - 1.0) / 6.0;
   double mn  = sy / nn;
   double vs  = syy / nn - mn * mn;
   if(vs <= 0.0) return false;
   double b   = (nn * sxy - sx * sy) / (nn * sxx - sx * sx);
   double a   = (sy - b * sx) / nn;
   double ssr = syy - a * sy - b * sxy;
   if(ssr < 0.0) ssr = 0.0;
   double m   = nn - 1.0, md = sd / m, vd = sdd / m - md * md;
   double flo = (vd > 0.0) ? MathSqrt(vd) * InpSigmaFloorMult : 0.0;
   fit   = ref + a + b * (nn - 1.0);
   sig_r = MathMax(MathSqrt(ssr / nn), flo);
   mean  = ref + mn;
   sd_s  = MathSqrt(vs);
   return (sig_r > 0.0);
}

bool ZAt(const double &c[], int i, double P, double &zr, double &zs, double &fit, double &sr, double &mean, double &ss) {
   if(!ZCore(c, i, P, fit, sr, mean, ss)) return false;
   zr = (P - fit) / sr;
   zs = (P - mean) / ss;
   return true;
}

//====================================================================
// 🏷️ ป้ายบนแท่ง (แบบเดียวกับ Counter EA)
//====================================================================
// Z_float ของแท่ง i (บวก = ราคาเปิดเหนือ SMA ตอนเปิดแท่ง)
bool FloatZ(int i, const double &open[], const double &close[], double &fz, double &mean, double &ss) {
   double zr, zs, fit, sr;
   fz = 0.0;
   if(!ZAt(close, i, open[i], zr, zs, fit, sr, mean, ss)) return false;
   fz = (open[i] - mean) / ss;
   return true;
}

void BarZLabels(int i, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[]) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)time[i]);
   double t2 = InpT2_Z, t3 = InpT3_Z, t4 = InpT4_Z, fz, fmean, fss;
   FloatZ(i, open, close, fz, fmean, fss);
   for(int side = 0; side < 2; side++) {
      string name = PFX + (side == 0 ? "ZL_S_" : "ZL_B_") + ts;
      double P    = (side == 0) ? high[i] : low[i];
      double zr, zs, fit, sr, mean, ss;
      bool   ok   = ZAt(close, i, P, zr, zs, fit, sr, mean, ss);
      double a_r  = (side == 0) ? zr : -zr, a_s = (side == 0) ? zs : -zs;
      bool   hit_r = ok && a_r > t2, hit_s = ok && a_s > t2;
      if(!InpShowBarZ || !(hit_r || hit_s)) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }

      // ระดับแบบ EA: T4 / T3 ตัวใดตัวหนึ่ง (ไม่ต้องลอย) | T2 ทั้งคู่ + Z_float > ขั้นต่ำ (ลอยมากพอ → ตัวเดียวก็ได้)
      double hi = MathMax(a_r, a_s), lo = MathMin(a_r, a_s);
      double zf = (side == 0) ? fz : -fz;
      bool   t2ok = zf > InpFloatMin && (lo > t2 || (zf > InpT2EitherFloat && hi > t2));
      int    tier = (hi > t4) ? 4 : (hi > t3) ? 3 : t2ok ? 2 : 0;
      color  clr  = (tier == 0) ? InpClrBarZOther : (side == 0 ? InpClrBarZSell : InpClrBarZBuy);
      double y    = (side == 0) ? (high[i] + off) : (low[i] - off);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, time[i], y);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_LOWER : ANCHOR_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetDouble(0,  name, OBJPROP_PRICE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("R%+.2f | S%+.2f", zr, zs));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s | Z_float %+.2f | %s",
                                   TimeToString(time[i], TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                   zr, (hit_r ? " ✓" : ""), zs, (hit_s ? " ✓" : ""), zf,
                                   (tier > 0 ? "ถึงระดับ T" + IntegerToString(tier) : "ถึงเกณฑ์ไม่ครบ")));
   }
}

// ป้าย Z_float: (ราคาเปิด − SMA ตอนเปิดแท่ง) ÷ SD — เหนือ SMA = ป้ายใต้ Low (ฝั่ง SELL) / ใต้ SMA = ป้ายเหนือ High (ฝั่ง BUY)
void FloatLabel(int i, bool live, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[]) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)time[i]);
   double fz, mean, ss;
   bool   ok  = FloatZ(i, open, close, fz, mean, ss);
   for(int side = 0; side < 2; side++) {
      string name = PFX + (side == 0 ? "FL_S_" : "FL_B_") + ts;
      double zf   = (side == 0) ? fz : -fz;
      bool   hit  = zf > InpFloatMarkZ;
      if(!InpShowFloatMark || !ok || !(hit || (live && zf > 0.0))) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }
      double y = (side == 0) ? (low[i] - off) : (high[i] + off);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, time[i], y);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_UPPER : ANCHOR_LOWER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetDouble(0,  name, OBJPROP_PRICE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, hit ? InpClrFloatMark : InpClrBarZOther);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("F%+.2f", zf));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ราคาเปิดลอยพ้น SMA (%s): Z_float %+.2f = (Open %s − SMA ตอนเปิดแท่ง %s) ÷ SD %.0f จุด",
                                   TimeToString(time[i], TIME_DATE|TIME_MINUTES), (side == 0 ? "ฝั่ง SELL" : "ฝั่ง BUY"), zf,
                                   DoubleToString(open[i], _Digits), DoubleToString(mean, _Digits), PriceToPts(ss)));
   }
}

//====================================================================
// 📏 เส้นระดับ / ป้าย Z สด
//====================================================================
void HLine(string name, double price, color clr, ENUM_LINE_STYLE style, string tip) {
   string nm = PFX + name;
   if(!InpShowLevelLines || price <= 0.0) { if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm); return; }
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetDouble(0, nm, OBJPROP_PRICE, price);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
}

void DrawLiveZ() {
   string nm = PFX + "LIVE_Z";
   if(!InpShowLiveZ || g_live_text == "") { if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm); return; }
   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, 0), g_live_bid, x, y)) return;
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   y = MathMax(8, MathMin(h - 8, y));
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpLiveZFontSize);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, MathMax(0, InpLiveZOffsetPx));
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  nm, OBJPROP_TEXT, g_live_text);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, g_live_clr);
   ObjectSetString(0,  nm, OBJPROP_TOOLTIP, g_live_tip);
}

//====================================================================
// 📊 ตารางถอยจากยอด (no new Z)
//   ทุกฝั่งคิดแบบ SELL: ฝั่ง BUY กลับเครื่องหมายราคา (s = −1) → High ของ BUY = −Low
//====================================================================
double M1Hi(int m, int s) { return (s > 0) ? g_m1[m].high : -g_m1[m].low; }
double M1Lo(int m, int s) { return (s > 0) ? g_m1[m].low  : -g_m1[m].high; }
double M1Op(int m, int s) { return s * g_m1[m].open; }
double M1Cl(int m, int s) { return s * g_m1[m].close; }

// Z ตัวใหญ่สุด (ในทิศของฝั่ง) ที่ราคา pT (ราคาที่กลับเครื่องหมายแล้ว) + SD20 ที่ราคานั้น
double ZSide(const double &c[], int i, double pT, int s, double &sig) {
   double fit, sr, mean, ss;
   sig = 0.0;
   double P = s * pT;
   if(!ZCore(c, i, P, fit, sr, mean, ss)) return -1.0e9;
   sig = ss;
   return MathMax(s * (P - fit) / sr, s * (P - mean) / ss);
}

void StatClear(StudyStat &x) { x.n = 0; x.nh = 0; x.sl = 0; x.rv = 0; x.un = 0; x.dist = 0.0; x.ev = 0.0; }

void StatAdd(StudyStat &x, int res, bool nh, double pnl, double dist) {
   x.n++;
   if(nh) x.nh++;
   if(res == RES_SL)      x.sl++;
   else if(res == RES_RV) x.rv++;
   else                   x.un++;
   x.dist += dist;
   x.ev   += PriceToPts(pnl);
}

// ผลของไม้สมมติ (เข้าที่ entryT หลังแท่ง M1 ที่ m0): อะไรเกิดก่อน — ทะลุยอด + SL / ถอยถึงเป้า / ครบเวลา
//   lo_same = ราคาที่ทำให้เกิดไม้ (เช็คเป้าก่อน), hi_same = แท่ง M1 นี้ Low มาก่อน High → High ของแท่งเดียวกันเกิดหลังจุดเข้า
//   คืน false = ข้อมูลยังไม่พอ (ไม้ล่าสุดที่ยังไม่จบ) → ไม่นับ
bool Resolve(int s, int m0, double lo_same, bool hi_same, double peakT, double sig, double entryT, datetime t_peak,
             int &res, bool &nh, double &pnl, datetime &t_res) {
   double   slT   = peakT + PtsToPrice(InpStudySL_Pts);
   double   tgT   = peakT - InpStudyTarget * sig;
   datetime t_end = t_peak + (datetime)InpStudyMin * 60;
   nh    = false;
   t_res = g_m1[m0].time;
   if(lo_same <= tgT) { res = RES_RV; pnl = entryT - tgT; return true; }
   if(hi_same) {
      double h0 = M1Hi(m0, s);
      if(h0 > peakT) nh = true;
      if(h0 >= slT) { res = RES_SL; pnl = entryT - slT; return true; }
   }
   for(int m = m0 + 1; m < g_m1_n; m++) {
      if(g_m1[m].time >= t_end) { res = RES_UN; pnl = entryT - M1Cl(m - 1, s); t_res = g_m1[m - 1].time; return true; }
      t_res = g_m1[m].time;
      double hi = M1Hi(m, s), lo = M1Lo(m, s);
      bool   hf = M1Op(m, s) > M1Cl(m, s);      // แท่งแดง (ในทิศของฝั่ง) = High มาก่อน Low
      if(hf) {
         if(hi > peakT) nh = true;
         if(hi >= slT) { res = RES_SL; pnl = entryT - slT; return true; }
         if(lo <= tgT) { res = RES_RV; pnl = entryT - tgT; return true; }
      } else {
         if(lo <= tgT) { res = RES_RV; pnl = entryT - tgT; return true; }
         if(hi > peakT) nh = true;
         if(hi >= slT) { res = RES_SL; pnl = entryT - slT; return true; }
      }
   }
   return false;
}

void AddSample(int l, int s, int kind, double key, datetime bar_t, datetime peak_t, datetime entry_t, datetime res_t,
               double z_peak, double peakT, double entryT, double sig, int res, bool nh, double pnl) {
   if(g_smp_n >= ArraySize(g_smp)) ArrayResize(g_smp, g_smp_n + 1, 20000);
   g_smp[g_smp_n].lvl     = l;
   g_smp[g_smp_n].side    = s;
   g_smp[g_smp_n].kind    = kind;
   g_smp[g_smp_n].key     = key;
   g_smp[g_smp_n].bar_t   = bar_t;
   g_smp[g_smp_n].peak_t  = peak_t;
   g_smp[g_smp_n].entry_t = entry_t;
   g_smp[g_smp_n].res_t   = res_t;
   g_smp[g_smp_n].z_peak  = z_peak;
   g_smp[g_smp_n].peak    = s * peakT;
   g_smp[g_smp_n].entry   = s * entryT;
   g_smp[g_smp_n].sig     = sig;
   g_smp[g_smp_n].res     = res;
   g_smp[g_smp_n].nh      = nh;
   g_smp[g_smp_n].pnl     = pnl;
   g_smp_n++;
}

// เหตุการณ์ของแท่งกราฟ i ฝั่ง s ระดับ l: แท่ง M1 [ma, mb)
void StudyBar(const double &c[], int i, datetime t0, int ma, int mb, int s, int l) {
   int      mins   = PeriodSeconds(_Period) / 60;
   bool     active = false;
   double   peak   = -DBL_MAX, sig = 0.0, zpk = 0.0;
   datetime tpk    = 0;
   bool     dd[N_DEP], dt[N_TIM];
   for(int b = 0; b < N_DEP; b++) dd[b] = false;
   for(int t = 0; t < N_TIM; t++) dt[t] = false;

   for(int m = ma; m < mb; m++) {
      int  off     = (int)((g_m1[m].time - t0) / 60);
      bool allowed = (off >= InpStudySkipFirstMin && off < mins - InpStudySkipLastMin);
      bool hf      = M1Op(m, s) > M1Cl(m, s);
      for(int q = 0; q < 2; q++) {
         bool   is_hi = ((q == 0) == hf);
         double p     = is_hi ? M1Hi(m, s) : M1Lo(m, s);
         if(is_hi) {
            if(p > peak) { peak = p; tpk = g_m1[m].time; if(active) zpk = ZSide(c, i, peak, s, sig); }
            if(!active && allowed) {
               double sg;
               if(ZSide(c, i, p, s, sg) > g_lvl[l]) { active = true; g_ev_n[l]++; zpk = ZSide(c, i, peak, s, sig); }
            }
            continue;
         }
         if(!active || !allowed || sig <= 0.0) continue;
         double ret = peak - p;
         for(int b = 0; b < N_DEP; b++) {
            if(dd[b] || g_dep_k[b] >= InpStudyTarget || ret < g_dep_k[b] * sig) continue;
            dd[b] = true;
            double entry = peak - g_dep_k[b] * sig, pnl;
            int      res;
            bool     nh;
            datetime tr;
            if(Resolve(s, m, p, !hf, peak, sig, entry, tpk, res, nh, pnl, tr)) {
               StatAdd(g_sd[l][b], res, nh, pnl, PriceToPts(g_dep_k[b] * sig));
               AddSample(l, s, 0, g_dep_k[b], t0, tpk, g_m1[m].time, tr, zpk, peak, entry, sig, res, nh, pnl);
            }
         }
      }
      if(!active || !allowed || sig <= 0.0) continue;
      for(int t = 0; t < N_TIM; t++) {
         if(dt[t] || g_m1[m].time - tpk < (datetime)g_tim_m[t] * 60) continue;
         dt[t] = true;
         double entry = M1Cl(m, s), pnl;
         if(entry <= peak - InpStudyTarget * sig) continue;    // สวนถึงเป้าไปแล้ว
         int      res;
         bool     nh;
         datetime tr;
         if(Resolve(s, m, DBL_MAX, false, peak, sig, entry, tpk, res, nh, pnl, tr)) {
            StatAdd(g_st[l][t], res, nh, pnl, (peak - entry) / sig);
            AddSample(l, s, 1, g_tim_m[t], t0, tpk, g_m1[m].time, tr, zpk, peak, entry, sig, res, nh, pnl);
         }
      }
   }
}

// คำนวณตารางใหม่ทั้งหมด (เรียกเมื่อขึ้นแท่งใหม่ของกราฟ) — คืน false = ข้อมูล M1 ยังไม่พร้อม ลองใหม่ภายหลัง
bool RunStudy(const double &c[], const datetime &time[], int rates_total) {
   g_smp_n = 0;
   for(int l = 0; l < N_LVL; l++) {
      g_ev_n[l] = 0;
      for(int b = 0; b < N_DEP; b++) StatClear(g_sd[l][b]);
      for(int t = 0; t < N_TIM; t++) StatClear(g_st[l][t]);
   }
   long per = PeriodSeconds(_Period);
   if(per <= 60) { g_study_msg = "ตารางถอยจากยอดต้องใช้กราฟ TF ใหญ่กว่า M1"; return true; }
   datetime t_to   = time[rates_total - 1] + (datetime)per;
   datetime t_from = t_to - (datetime)InpStudyDays * 86400;
   g_m1_n = CopyRates(_Symbol, PERIOD_M1, t_from, t_to, g_m1);
   if(g_m1_n <= 0) { g_m1_n = 0; g_study_msg = "กำลังโหลดข้อมูล M1 ..."; return false; }
   g_m1_from = g_m1[0].time;
   g_m1_to   = g_m1[g_m1_n - 1].time;

   double zmin = MathMin(g_lvl[0], MathMin(g_lvl[1], g_lvl[2]));
   int    mp   = 0;
   for(int i = g_warm; i < rates_total - 1; i++) {      // เฉพาะแท่งที่ปิดแล้ว
      datetime t0 = time[i], t1 = t0 + (datetime)per;
      if(t0 < g_m1_from) continue;
      while(mp < g_m1_n && g_m1[mp].time < t0) mp++;
      int mb = mp;
      while(mb < g_m1_n && g_m1[mb].time < t1) mb++;
      for(int s = 1; s >= -1; s -= 2) {
         double mx = -DBL_MAX, sg;
         for(int m = mp; m < mb; m++) mx = MathMax(mx, M1Hi(m, s));
         if(mb <= mp || ZSide(c, i, mx, s, sg) <= zmin) continue;   // ทั้งแท่งไม่ถึงระดับต่ำสุด → ข้าม
         for(int l = 0; l < N_LVL; l++) StudyBar(c, i, t0, mp, mb, s, l);
      }
      mp = mb;
   }
   ArrayFree(g_m1);
   g_m1_n = 0;
   g_study_msg = "";
   return true;
}

void StudyLine(int row, string text, color clr) {
   string nm = PFX + "ST_" + IntegerToString(row);
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 12 + row * 15);
      ObjectSetString(0,  nm, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0,  nm, OBJPROP_TEXT, text);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
}

string StatRow(string head, const StudyStat &x, string dist_fmt) {
   double n = MathMax(1, x.n);
   return StringFormat("%-10s %5d %6.1f%% %6.1f%% %6.1f%% %6.1f%% " + dist_fmt + " %+8.0f",
                       head, x.n, 100.0 * x.nh / n, 100.0 * x.sl / n, 100.0 * x.rv / n, 100.0 * x.un / n,
                       x.dist / n, x.ev / n);
}

string ResCode(int res) { return (res == RES_SL) ? "CONT" : (res == RES_RV) ? "REV" : "UNC"; }

string StudyFileBase() {
   string tf = EnumToString((ENUM_TIMEFRAMES)_Period);
   StringReplace(tf, "PERIOD_", "");
   return "7LCTX_Study_" + _Symbol + "_" + tf;
}

string SummaryCsvRow(int l, string table, double key, const StudyStat &x, int dist_dig) {
   double n = MathMax(1, x.n);
   return StringFormat("%.2f,%d,%s,%.2f,%d,%.1f,%.1f,%.1f,%.1f,%s,%.0f\r\n", g_lvl[l], g_ev_n[l], table, key, x.n,
                       100.0 * x.nh / n, 100.0 * x.sl / n, 100.0 * x.rv / n, 100.0 * x.un / n,
                       DoubleToString(x.dist / n, dist_dig), x.ev / n);
}

// บันทึกผลตาราง (สรุป + ทุกไม้สมมติ) ลง MQL5/Files — เปิดด้วย Excel ได้
void WriteStudyCSV() {
   if(g_study_bar == 0 || g_study_msg != "") { Print("⚠️ ตารางถอยจากยอดยังคำนวณไม่เสร็จ — ลองใหม่อีกครั้ง"); return; }
   string fs = StudyFileBase() + ".csv", ft = StudyFileBase() + "_trades.csv";
   int h = FileOpen(fs, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fs, GetLastError()); return; }
   FileWriteString(h, StringFormat("# m1_from=%s m1_to=%s cont=peak+%.0fpts rev=peak-%.1fsigma wait=%dmin skip_first=%dmin skip_last=%dmin sigma=SD20_at_peak\r\n",
                                   TimeToString(g_m1_from, TIME_DATE), TimeToString(g_m1_to, TIME_DATE), InpStudySL_Pts, InpStudyTarget,
                                   InpStudyMin, InpStudySkipFirstMin, InpStudySkipLastMin));
   FileWriteString(h, "level_z,events,table,row,trades,new_peak_pct,cont_pct,rev_pct,unc_pct,avg_pullback,ev_pts\r\n");
   for(int l = 0; l < N_LVL; l++) {
      for(int b = 0; b < N_DEP; b++)
         if(g_dep_k[b] < InpStudyTarget) FileWriteString(h, SummaryCsvRow(l, "pullback_dz", g_dep_k[b], g_sd[l][b], 0));
      for(int t = 0; t < N_TIM; t++) FileWriteString(h, SummaryCsvRow(l, "no_new_peak_min", g_tim_m[t], g_st[l][t], 3));
   }
   FileClose(h);

   h = FileOpen(ft, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", ft, GetLastError()); return; }
   FileWriteString(h, "level_z,side,table,row,bar_time,peak_time,entry_time,result_time,z_peak,peak,entry,sigma_pts,pullback_pts,pullback_dz,result,new_peak,pnl_pts\r\n");
   for(int k = 0; k < g_smp_n; k++) {
      double d = MathAbs(g_smp[k].peak - g_smp[k].entry);
      FileWriteString(h, StringFormat("%.2f,%s,%s,%.2f,%s,%s,%s,%s,%.3f,%s,%s,%.0f,%.0f,%.3f,%s,%d,%.0f\r\n",
                                      g_lvl[g_smp[k].lvl], (g_smp[k].side > 0 ? "SELL" : "BUY"), (g_smp[k].kind == 0 ? "pullback_dz" : "no_new_peak_min"),
                                      g_smp[k].key, TimeToString(g_smp[k].bar_t, TIME_DATE|TIME_MINUTES),
                                      TimeToString(g_smp[k].peak_t, TIME_DATE|TIME_MINUTES), TimeToString(g_smp[k].entry_t, TIME_DATE|TIME_MINUTES),
                                      TimeToString(g_smp[k].res_t, TIME_DATE|TIME_MINUTES), g_smp[k].z_peak,
                                      DoubleToString(g_smp[k].peak, _Digits), DoubleToString(g_smp[k].entry, _Digits),
                                      PriceToPts(g_smp[k].sig), PriceToPts(d), (g_smp[k].sig > 0.0 ? d / g_smp[k].sig : 0.0),
                                      ResCode(g_smp[k].res), (g_smp[k].nh ? 1 : 0), PriceToPts(g_smp[k].pnl)));
   }
   FileClose(h);
   PrintFormat("💾 บันทึกตารางถอยจากยอด → MQL5\\Files\\%s (สรุป) + %s (%d ไม้)", fs, ft, g_smp_n);
}

void DrawStudyButtons(int top_y) {
   for(int l = 0; l < N_LVL; l++) {
      string nm = BTN_PFX + IntegerToString(l);
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_XSIZE, 64);
         ObjectSetInteger(0, nm, OBJPROP_YSIZE, 20);
         ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10 + (N_LVL - 1 - l) * 70 + 64);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, top_y + 20);
      ObjectSetString(0,  nm, OBJPROP_TEXT, StringFormat("Z > %.1f", g_lvl[l]));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, (l == g_sel) ? clrSeaGreen : clrDimGray);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP, StringFormat("แสดงตารางถอยจากยอดของเหตุการณ์ Z ตัวใดตัวหนึ่ง > %.2f", g_lvl[l]));
   }
   if(ObjectFind(0, BTN_CSV) < 0) {
      ObjectCreate(0, BTN_CSV, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, BTN_CSV, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, BTN_CSV, OBJPROP_XSIZE, 64);
      ObjectSetInteger(0, BTN_CSV, OBJPROP_YSIZE, 20);
      ObjectSetString(0,  BTN_CSV, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, BTN_CSV, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, BTN_CSV, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, BTN_CSV, OBJPROP_BGCOLOR, clrSteelBlue);
      ObjectSetInteger(0, BTN_CSV, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, BTN_CSV, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  BTN_CSV, OBJPROP_TEXT, "💾 CSV");
      ObjectSetString(0,  BTN_CSV, OBJPROP_TOOLTIP, "บันทึกผลตาราง (ทุกระดับ + ทุกไม้สมมติ) ลง MQL5\\Files เปิดด้วย Excel ได้");
   }
   ObjectSetInteger(0, BTN_CSV, OBJPROP_XDISTANCE, 10 + N_LVL * 70 + 64);
   ObjectSetInteger(0, BTN_CSV, OBJPROP_YDISTANCE, top_y + 20);
   ObjectSetInteger(0, BTN_CSV, OBJPROP_STATE, false);
}

void DrawStudy() {
   ObjectsDeleteAll(0, PFX + "ST_");
   if(!InpShowStudy) { ObjectsDeleteAll(0, BTN_PFX); ObjectDelete(0, BTN_CSV); return; }
   int l = g_sel;
   // แถว EV ดีสุด (ไม้พอ) ของแต่ละตาราง
   int bd = -1, bt = -1;
   for(int b = 0; b < N_DEP; b++)
      if(g_sd[l][b].n >= InpStudyMinN && (bd < 0 || g_sd[l][b].ev / g_sd[l][b].n > g_sd[l][bd].ev / g_sd[l][bd].n)) bd = b;
   for(int t = 0; t < N_TIM; t++)
      if(g_st[l][t].n >= InpStudyMinN && (bt < 0 || g_st[l][t].ev / g_st[l][t].n > g_st[l][bt].ev / g_st[l][bt].n)) bt = t;

   int row = 0;   // แถว 0 = ล่างสุด
   for(int t = N_TIM - 1; t >= 0; t--)
      StudyLine(row++, StatRow(StringFormat(">= %d min", g_tim_m[t]), g_st[l][t], "%7.2f"), (t == bt) ? InpClrTableBest : InpClrTable);
   StudyLine(row++, "ไม่มียอดใหม่  ไม้ ยอดใหม่ พุ่งต่อ    สวน  ไม่ชัด ถอย(ΔZ)   EV(จุด)", InpClrTable);
   for(int b = N_DEP - 1; b >= 0; b--) {
      if(g_dep_k[b] >= InpStudyTarget) continue;
      StudyLine(row++, StatRow(StringFormat("dZ >= %.2f", g_dep_k[b]), g_sd[l][b], "%7.0f"), (b == bd) ? InpClrTableBest : InpClrTable);
   }
   StudyLine(row++, "ถอยจากยอด    ไม้ ยอดใหม่ พุ่งต่อ    สวน  ไม่ชัด ระยะ(จุด) EV(จุด)", InpClrTable);
   StudyLine(row++, StringFormat("พุ่งต่อ = ทะลุยอด + %.0f จุด | สวน = ถอยถึง %.1fσ | รอผล %d นาทีหลังยอด | σ = SD20 ตอนแตะยอด | ไม่นับ %d นาทีแรก / %d นาทีท้ายแท่ง",
                                 InpStudySL_Pts, InpStudyTarget, InpStudyMin, InpStudySkipFirstMin, InpStudySkipLastMin), InpClrTable);
   string head = (g_study_msg != "") ? g_study_msg
               : StringFormat("📊 ถอยจากยอด | Z ตัวใดตัวหนึ่ง > %.2f | %d เหตุการณ์ (SELL + BUY) | M1 %s → %s",
                              g_lvl[l], g_ev_n[l], TimeToString(g_m1_from, TIME_DATE), TimeToString(g_m1_to, TIME_DATE));
   StudyLine(row++, head, InpClrTable);
   DrawStudyButtons(12 + row * 15);
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
void SetPlot(int plot, color clr) {
   if(!InpShowHistLines) PlotIndexSetInteger(plot, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(plot, PLOT_LINE_COLOR, clr);
   PlotIndexSetInteger(plot, PLOT_DRAW_BEGIN, g_warm);
   PlotIndexSetDouble(plot, PLOT_EMPTY_VALUE, EMPTY_VALUE);
}

int OnInit() {
   if(InpZ_Period < 5 || InpSigmaFloorMult < 0.0 || InpT2_Z <= 0.0 || InpT3_Z < InpT2_Z || InpT4_Z < InpT3_Z || InpFloatMin < 0.0 ||
      InpBarZBars < 0 || InpStudyDays < 1 || InpStudyZ1 <= 0.0 || InpStudyZ2 <= 0.0 || InpStudyZ3 <= 0.0 ||
      InpStudySL_Pts < 0.0 || InpStudyTarget <= 0.0 || InpStudyMin < 1 || InpStudySkipFirstMin < 0 || InpStudySkipLastMin < 0) {
      Print("❌ ค่า Input ไม่ถูกต้อง (หน้าต่าง ≥ 5, T2 ≤ T3 ≤ T4, ค่าตารางต้องเป็นบวก)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   g_warm  = InpZ_Period + 2;
   g_lvl[0] = InpStudyZ1; g_lvl[1] = InpStudyZ2; g_lvl[2] = InpStudyZ3;
   if(GlobalVariableCheck(GV_LVL)) g_sel = (int)MathMax(0, MathMin(N_LVL - 1, GlobalVariableGet(GV_LVL)));

   SetIndexBuffer(0, bR,  INDICATOR_DATA);
   SetIndexBuffer(1, bRp, INDICATOR_DATA);
   SetIndexBuffer(2, bRm, INDICATOR_DATA);
   SetIndexBuffer(3, bS,  INDICATOR_DATA);
   SetIndexBuffer(4, bSp, INDICATOR_DATA);
   SetIndexBuffer(5, bSm, INDICATOR_DATA);
   SetPlot(0, InpClrZCenter);
   SetPlot(1, InpClrZSellLine);
   SetPlot(2, InpClrZBuyLine);
   SetPlot(3, InpClrSmaCenter);
   SetPlot(4, InpClrSmaSellLine);
   SetPlot(5, InpClrSmaBuyLine);

   IndicatorSetString(INDICATOR_SHORTNAME, "7L Z SMA / Reg");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   ObjectsDeleteAll(0, PFX);
   g_live_text   = "";
   g_study_bar   = 0;
   g_study_retry = 0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, PFX);
   ArrayFree(g_m1);
   ArrayFree(g_smp);
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
   if(rates_total < g_warm + 5) return(0);
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(start == 0) {
      ObjectsDeleteAll(0, PFX + "ZL_");
      ObjectsDeleteAll(0, PFX + "FL_");
      g_study_bar = 0;
   }
   int last = rates_total - 1;
   int from = (InpBarZBars > 0) ? MathMax(g_warm, rates_total - InpBarZBars) : g_warm;
   double t2 = InpT2_Z;

   for(int i = start; i < rates_total; i++) {
      bR[i] = EMPTY_VALUE; bRp[i] = EMPTY_VALUE; bRm[i] = EMPTY_VALUE;
      bS[i] = EMPTY_VALUE; bSp[i] = EMPTY_VALUE; bSm[i] = EMPTY_VALUE;
      if(i < g_warm) continue;

      // เส้นย้อนหลัง (ณ ราคาปิด) ± เกณฑ์ T2
      double zr, zs, fit, sr, mean, ss;
      if(ZAt(close, i, close[i], zr, zs, fit, sr, mean, ss)) {
         bR[i] = fit;  bRp[i] = fit + t2 * sr;  bRm[i] = fit - t2 * sr;
         bS[i] = mean; bSp[i] = mean + t2 * ss; bSm[i] = mean - t2 * ss;
      }

      // ป้ายบนแท่ง (แท่งปัจจุบันประเมินใหม่ทุก Tick)
      if(i >= from) {
         BarZLabels(i, time, open, high, low, close);
         FloatLabel(i, (i == last), time, open, high, low, close);
      }
   }
   // ลบป้ายที่หลุดช่วงแสดง
   if(InpBarZBars > 0 && prev_calculated > 0 && rates_total > prev_calculated) {
      for(int k = MathMax(0, prev_calculated - InpBarZBars - 1); k < from; k++) {
         string ts = IntegerToString((long)time[k]);
         ObjectDelete(0, PFX + "ZL_S_" + ts); ObjectDelete(0, PFX + "ZL_B_" + ts);
         ObjectDelete(0, PFX + "FL_S_" + ts); ObjectDelete(0, PFX + "FL_B_" + ts);
      }
   }

   // เส้นระดับ + ป้าย Z สด ณ ราคาล่าสุด
   double zr, zs, fit, sr, mean, ss;
   if(ZAt(close, last, close[last], zr, zs, fit, sr, mean, ss)) {
      HLine("R_MAIN", fit,            InpClrZCenter,     STYLE_DOT,     "[Regression] เส้นกลาง Z = 0");
      HLine("R_SELL", fit + t2 * sr,  InpClrZSellLine,   STYLE_DASH,    StringFormat("[Regression] SELL T2 Z > +%.2f", t2));
      HLine("R_BUY",  fit - t2 * sr,  InpClrZBuyLine,    STYLE_DASH,    StringFormat("[Regression] BUY T2 Z < −%.2f", t2));
      HLine("S_MAIN", mean,           InpClrSmaCenter,   STYLE_DOT,     "[SMA20] เส้นกลาง Z = 0");
      HLine("S_SELL", mean + t2 * ss, InpClrSmaSellLine, STYLE_DASHDOT, StringFormat("[SMA20] SELL T2 Z > +%.2f", t2));
      HLine("S_BUY",  mean - t2 * ss, InpClrSmaBuyLine,  STYLE_DASHDOT, StringFormat("[SMA20] BUY T2 Z < −%.2f", t2));
      double z = (MathAbs(zr) >= MathAbs(zs)) ? zr : zs;
      g_live_clr  = (z > t2) ? InpClrLiveSell : (z < -t2) ? InpClrLiveBuy
                  : (MathAbs(z) >= t2 - NEAR_ZONE) ? InpClrLiveNear : InpClrLiveNormal;
      g_live_text = StringFormat("R %+.2f | S %+.2f ▶", zr, zs);
      g_live_bid  = close[last];
      g_live_tip  = StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s) | เกณฑ์ T2 %.2f / T3 %.2f / T4 %.2f",
                                 zr, DoubleToString(fit, _Digits), zs, DoubleToString(mean, _Digits), t2, InpT3_Z, InpT4_Z);
      DrawLiveZ();
   }

   // ตารางถอยจากยอด: คำนวณใหม่เมื่อขึ้นแท่งใหม่ (ข้อมูล M1 ยังไม่พร้อม → ลองใหม่ทุก 5 วินาที)
   if(InpShowStudy && time[last] != g_study_bar && GetTickCount() >= g_study_retry) {
      if(RunStudy(close, time, rates_total)) g_study_bar = time[last];
      else                                   g_study_retry = GetTickCount() + 5000;
      DrawStudy();
   }
   return(rates_total);
}

// เลื่อน/ซูมกราฟ → จัดตำแหน่งป้าย Z สดใหม่ | คลิกปุ่มระดับ → สลับตาราง | ปุ่ม CSV → บันทึกไฟล์
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_CSV) {
      WriteStudyCSV();
      ObjectSetInteger(0, BTN_CSV, OBJPROP_STATE, false);
      ChartRedraw(0);
      return;
   }
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BTN_PFX) == 0) {
      g_sel = (int)MathMax(0, MathMin(N_LVL - 1, StringToInteger(StringSubstr(sparam, StringLen(BTN_PFX)))));
      GlobalVariableSet(GV_LVL, g_sel);
      DrawStudy();
      ChartRedraw(0);
      return;
   }
   if(id != CHARTEVENT_CHART_CHANGE) return;
   DrawLiveZ();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
