//+------------------------------------------------------------------+
//|                                     Seven_Lines_Context_Ind.mq5  |
//|        เส้นบริบทเทียบกับ Z (แยกออกจาก Seven_Lines_Counter_EA)     |
//+------------------------------------------------------------------+
//
// 🔬 เส้นบริบท — คำนวณบน TF ของกราฟด้วย Indicator Buffer → ย้อนหลังได้เท่าที่กราฟมีแท่ง
//  ① Z ของ TF ใหญ่ (ค่าเริ่มต้น H1, สูตรเดียวกับ Counter EA) — เส้นกลาง Regression ± เกณฑ์ × σ
//  ② VWAP รายวัน ± 1σ / 2σ (tick volume ของแท่งบนกราฟ, เริ่มใหม่ทุกวันตามเวลาเซิร์ฟเวอร์)
//  ③ Keltner (EMA20 ± 1.5 ATR) — ขอบเปลี่ยนสีเมื่อ Squeeze (Bollinger SMA20 ± 2 SD อยู่ในกรอบ Keltner)
//  ④ High / Low / Close วันก่อน + เลขกลม $10 / $50
//  ⑤ พัดเส้น 7 เส้น (ค่าในป้ายเท่านั้น)
//  ⑥ EMA 200
//
// 🏷️ ป้ายค่า Z ของแต่ละเส้น: แท่งที่ Z_reg และ Z_SMA ที่ High (SELL) / Low (BUY) เกิน ±2.00 ทั้งคู่
//  • Z ของแท่ง = แท่งปิด n−1 แท่งก่อนหน้า + ราคาสุดขั้วของแท่งนั้น (เหมือนป้าย Z ใน Counter EA)
//  • ค่าของแต่ละเส้นวัดที่ราคาสุดขั้วนั้น โดยใช้ค่าเส้นของแท่งก่อนหน้า (ไม่มองอนาคต)
//    TF ใหญ่ = Z_reg / Z_SMA ของ TF ใหญ่ (แท่งที่ปิดแล้ว + ราคาสุดขั้ว) | VW = (ราคา − VWAP) ÷ σ ของ VWAP
//    KC = (ราคา − EMA20) ÷ ATR | E200 = (ราคา − EMA200) ÷ ATR | PDH / PDL = (ราคา − High / Low วันก่อน) ÷ ATR
//    พัด = (เส้นสูงสุด − ต่ำสุด ของเส้น 7 เส้น) ÷ SD20, ลำดับ +6 (เส้นเร็วอยู่เหนือ Main ครบ) … −6
//  • แสดงอย่างเดียว ไม่มีสัญญาณซื้อขาย
//
#property copyright   "Commander's Quant System"
#property version     "1.00"
#property description "เส้นบริบท (TF ใหญ่ / VWAP / Keltner / วันก่อน / EMA ยาว) + ป้ายค่า Z ของแต่ละเส้นเมื่อ Z เกินเกณฑ์"
#property indicator_chart_window
#property indicator_buffers 25
#property indicator_plots   15

#property indicator_label1  "Keltner กลาง (EMA)"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_DOT
#property indicator_label2  "Keltner บน"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_label3  "Keltner ล่าง"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_label4  "EMA ยาว"
#property indicator_type4   DRAW_LINE
#property indicator_width4  2
#property indicator_label5  "VWAP"
#property indicator_type5   DRAW_LINE
#property indicator_width5  2
#property indicator_label6  "VWAP +1σ"
#property indicator_type6   DRAW_LINE
#property indicator_style6  STYLE_DOT
#property indicator_label7  "VWAP −1σ"
#property indicator_type7   DRAW_LINE
#property indicator_style7  STYLE_DOT
#property indicator_label8  "VWAP +2σ"
#property indicator_type8   DRAW_LINE
#property indicator_style8  STYLE_DASH
#property indicator_label9  "VWAP −2σ"
#property indicator_type9   DRAW_LINE
#property indicator_style9  STYLE_DASH
#property indicator_label10 "TF ใหญ่: เส้นกลาง Regression"
#property indicator_type10  DRAW_LINE
#property indicator_style10 STYLE_DASH
#property indicator_label11 "TF ใหญ่: +σ"
#property indicator_type11  DRAW_LINE
#property indicator_style11 STYLE_DASHDOT
#property indicator_label12 "TF ใหญ่: −σ"
#property indicator_type12  DRAW_LINE
#property indicator_style12 STYLE_DASHDOT
#property indicator_label13 "High วันก่อน"
#property indicator_type13  DRAW_LINE
#property indicator_label14 "Low วันก่อน"
#property indicator_type14  DRAW_LINE
#property indicator_label15 "Close วันก่อน"
#property indicator_type15  DRAW_LINE
#property indicator_style15 STYLE_DOT

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== Z & ป้ายค่า (สูตรเดียวกับ Counter EA) ==="
input int             InpZ_Period          = 20;         // จำนวนแท่งของ Z (ทั้ง TF กราฟและ TF ใหญ่)
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z_reg ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง
input bool            InpShowLabels        = true;       // แสดงป้ายค่าของแต่ละเส้นบนแท่งที่ Z เกินเกณฑ์
input double          InpLabelZ            = 2.00;       // ป้าย: Z_reg และ Z_SMA เกิน ±ค่านี้ทั้งคู่
input int             InpLabelBars         = 0;          // ป้าย: ย้อนหลังกี่แท่ง (0 = ทั้งหมด)
input int             InpLabelFontSize     = 7;          // ป้าย: ขนาดตัวอักษร
input double          InpLabelOffset_Pts   = 300.0;      // ป้าย: ระยะห่างจากไส้เทียน (จุด)

input group "=== ① Z ของ TF ใหญ่ ==="
input ENUM_TIMEFRAMES InpHTF               = PERIOD_H1;  // TF ใหญ่
input bool            InpShowHTF           = true;       // วาดเส้นกลาง Regression ± σ ของ TF ใหญ่
input double          InpHTFBandZ          = 2.00;       // เส้นขอบ = เส้นกลาง ± ค่านี้ × σ

input group "=== ② VWAP รายวัน ==="
input bool            InpShowVWAP          = true;       // วาด VWAP ± 1σ / 2σ

input group "=== ③ Keltner Channel ==="
input bool            InpShowKeltner       = true;       // วาด Keltner (ขอบเปลี่ยนสีตอน Squeeze)
input int             InpKC_Period         = 20;         // Period ของ EMA / ATR
input double          InpKC_Mult           = 1.5;        // ตัวคูณ ATR
input double          InpSqueezeBB_Mult    = 2.0;        // Squeeze = Bollinger (SMA ± ค่านี้ × SD) อยู่ในกรอบ Keltner

input group "=== ④ วันก่อน / เลขกลม ==="
input bool            InpShowPrevDay       = true;       // วาด High / Low / Close ของวันก่อน
input bool            InpShowRound         = true;       // วาดเลขกลมรอบราคาปัจจุบัน
input double          InpRoundStep         = 10.0;       // ระยะเลขกลม (ราคา, ทอง = $10)
input double          InpRoundMajor        = 50.0;       // เลขกลมหลัก (เส้นเข้ม, ราคา)
input int             InpRoundCount        = 5;          // จำนวนเส้นเลขกลมแต่ละฝั่งของราคา

input group "=== ⑤ พัดเส้น 7 เส้น / ⑥ EMA ยาว ==="
input int             InpFastPeriod        = 10;         // Fast Period ของเส้น L1-L5 (เหมือน Counter EA)
input bool            InpShowEMALong       = true;       // วาด EMA ยาว
input int             InpEMALong           = 200;        // Period ของ EMA ยาว

input group "=== สี ==="
input color           InpClrKeltner        = clrMediumSlateBlue; // Keltner
input color           InpClrSqueeze        = clrMagenta;        // ขอบ Keltner ตอน Squeeze
input color           InpClrEMALong        = clrWhiteSmoke;     // EMA ยาว
input color           InpClrVWAP           = clrKhaki;          // VWAP
input color           InpClrVWAPBand       = clrDarkKhaki;      // แถบ VWAP ± σ
input color           InpClrHTF            = clrCoral;          // เส้น TF ใหญ่
input color           InpClrPrevDay        = clrLightGray;      // H / L / C วันก่อน
input color           InpClrRound          = C'70,70,70';       // เลขกลม
input color           InpClrRoundMajor     = C'120,120,120';    // เลขกลมหลัก
input color           InpClrLabelSell      = clrOrangeRed;      // ป้ายฝั่ง SELL (เหนือแท่ง)
input color           InpClrLabelBuy       = clrDeepSkyBlue;    // ป้ายฝั่ง BUY (ใต้แท่ง)

//====================================================================
// 🔒 INTERNAL
//====================================================================
const string PFX     = "7LCTX_";
const long   DAY_SEC = 86400;

// --- Buffers (เรียงเก่า→ใหม่) ---
double bKcMid[], bKcUp[], bKcUpC[], bKcLo[], bKcLoC[], bEmaL[];
double bVw[], bVwP1[], bVwM1[], bVwP2[], bVwM2[];
double bHc[], bHp[], bHm[], bPdh[], bPdl[], bPdc[];
double cAtr[], cVv[], cV1[], cV2[], cDayH[], cDayL[], cEmaF[], cSqz[];

double   g_pmult   = 1.0;
double   g_alma_w[];
double   g_alma_wsum = 0.0;
MqlRates g_h[];                // แท่ง TF ใหญ่
double   g_hc[];               // ราคาปิด TF ใหญ่
datetime g_h_bar   = 0;        // แท่งปัจจุบันของ TF ใหญ่ตอนโหลดล่าสุด
int      g_h_fail  = 0;
double   g_rn_mid  = 0.0;
int      g_warm    = 0;        // แท่งแรกที่ค่าทุกเส้นนิ่งพอใช้ในป้าย

//====================================================================
// 🧰 HELPERS
//====================================================================
double   PtsToPrice(double pts) { return pts * g_pmult * _Point; }
datetime DayStart(datetime t)   { return t - (datetime)((long)t % DAY_SEC); }

string HTFName() {
   string s = EnumToString(InpHTF);
   StringReplace(s, "PERIOD_", "");
   return s;
}

// Z ที่ราคา price โดยใช้ราคาปิด c[last−n+2 .. last] เป็น n−1 แท่งก่อนหน้า (ตรงกับ Z engine ของ Counter EA)
//   fit = ราคาเส้นถดถอยที่แท่งปัจจุบัน, sig = ตัวหาร Z_reg, slope = ความชัน (ราคาต่อแท่ง)
bool ZAt(const double &c[], int last, double price, double &zr, double &zs, double &fit, double &sig, double &slope) {
   int n = InpZ_Period;
   if(last - n + 2 < 0) return false;
   double ref = c[last];
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n - 1; k++) {
      int    idx = last - (n - 2) + k;
      double y   = c[idx] - ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[idx] - c[idx - 1]; sd += d; sdd += d * d; }
   }
   double y_last = price - ref;
   sy += y_last; sxy += (n - 1) * y_last; syy += y_last * y_last;
   double d0 = price - c[last];
   sd += d0; sdd += d0 * d0;

   double nn  = (double)n;
   double sx  = nn * (nn - 1.0) / 2.0;
   double sxx = (nn - 1.0) * nn * (2.0 * nn - 1.0) / 6.0;
   double mean   = sy / nn;
   double var_sm = syy / nn - mean * mean;
   if(var_sm <= 0.0) return false;
   double b  = (nn * sxy - sx * sy) / (nn * sxx - sx * sx);
   double a  = (sy - b * sx) / nn;
   double ft = a + b * (nn - 1.0);
   double ssr = syy - a * sy - b * sxy;
   if(ssr < 0.0) ssr = 0.0;
   double sd_res = MathSqrt(ssr / nn);
   double m      = nn - 1.0;
   double md     = sd / m;
   double var_d  = sdd / m - md * md;
   double sd_min = (var_d > 0.0) ? MathSqrt(var_d) * InpSigmaFloorMult : 0.0;
   sig = MathMax(sd_res, sd_min);
   if(sig <= 0.0) return false;
   zr    = (y_last - ft) / sig;
   zs    = (y_last - mean) / MathSqrt(var_sm);
   fit   = ref + ft;
   slope = b;
   return true;
}

double SDAt(const double &c[], int k, int n) {
   double s = 0.0, ss = 0.0, ref = c[k];
   for(int i = k - n + 1; i <= k; i++) { double d = c[i] - ref; s += d; ss += d * d; }
   double m = s / n, v = ss / n - m * m;
   return (v > 0.0) ? MathSqrt(v) : 0.0;
}

//--- เส้น 7 เส้น (สูตรเดียวกับ Counter EA / Indicator v8.82) สำหรับพัด ---
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

// พัดเส้น 7 เส้นที่แท่ง e: ความกว้าง ÷ SD20 และลำดับ (+6 … −6)
bool FanAt(const double &c[], int e, double &width, int &order) {
   int    n  = InpZ_Period, fp = InpFastPeriod;
   double sd = SDAt(c, e, n);
   if(sd <= 0.0) return false;
   double mainv = LnSMA(c, e, n);
   double fast[6];
   fast[0] = cEmaF[e];
   fast[1] = LnWMA(c, e, fp);
   fast[2] = LnHMA(c, e, fp);
   fast[3] = LnLSMA(c, e, fp);
   fast[4] = LnALMA(c, e, fp);
   fast[5] = LnKinematic(c, e);
   double hi = mainv, lo = mainv;
   order = 0;
   for(int L = 0; L < 6; L++) {
      hi = MathMax(hi, fast[L]);
      lo = MathMin(lo, fast[L]);
      if(fast[L] > mainv) order++;
      else if(fast[L] < mainv) order--;
   }
   width = (hi - lo) / sd;
   return true;
}

//--- TF ใหญ่ ---
// โหลดแท่ง TF ใหญ่ใหม่เมื่อขึ้นแท่งใหม่ (ครอบตั้งแต่แท่งแรกของกราฟ)
bool LoadHTF(datetime from) {
   datetime h0 = iTime(_Symbol, InpHTF, 0);
   if(h0 == 0) return false;
   if(h0 == g_h_bar && ArraySize(g_hc) > 0) return true;
   long per = PeriodSeconds(InpHTF);
   int  got = CopyRates(_Symbol, InpHTF, (datetime)((long)from - per * (InpZ_Period + 2)), (datetime)((long)TimeCurrent() + per), g_h);
   if(got <= 0) return false;
   ArrayResize(g_hc, got);
   for(int i = 0; i < got; i++) g_hc[i] = g_h[i].close;
   g_h_bar = h0;
   return true;
}

// index สุดท้ายของแท่ง TF ใหญ่ที่ปิดแล้ว ณ เวลา t (−1 = ไม่มี)
int HTFIdx(datetime t) {
   long per = PeriodSeconds(InpHTF);
   int  lo = 0, hi = ArraySize(g_h) - 1, ans = -1;
   while(lo <= hi) {
      int mid = (lo + hi) / 2;
      if((long)g_h[mid].time + per <= (long)t) { ans = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   return ans;
}

//====================================================================
// 🏷️ ป้ายค่าของแต่ละเส้นบนแท่งที่ Z เกินเกณฑ์
//====================================================================
string Sgn(double v, int digits) { return (v >= 0.0 ? "+" : "") + DoubleToString(v, digits); }

void LabelBar(int i, const datetime &time[], const double &high[], const double &low[], const double &close[]) {
   string ts = IntegerToString((long)time[i]);
   for(int side = 0; side < 2; side++) {
      string name  = PFX + (side == 0 ? "LS_" : "LB_") + ts;
      double price = (side == 0) ? high[i] : low[i];
      double zr = 0.0, zs = 0.0, fit, sig, slope;
      bool   ok  = (i >= g_warm) && ZAt(close, i - 1, price, zr, zs, fit, sig, slope);
      bool   hit = ok && ((side == 0) ? (zr > InpLabelZ && zs > InpLabelZ) : (zr < -InpLabelZ && zs < -InpLabelZ));
      if(!hit) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }

      int    e   = i - 1;
      double atr = cAtr[e];
      string txt = StringFormat("R%s S%s", Sgn(zr, 2), Sgn(zs, 2));
      string tip = StringFormat("%s %s @ %s | Z_reg %s / Z_SMA %s",
                                (side == 0 ? "High" : "Low"), TimeToString(time[i], TIME_DATE|TIME_MINUTES),
                                DoubleToString(price, _Digits), Sgn(zr, 2), Sgn(zs, 2));
      // ① TF ใหญ่
      int    hk = HTFIdx(time[i]);
      double hzr, hzs, hfit, hsig, hslope;
      if(hk >= 0 && ZAt(g_hc, hk, price, hzr, hzs, hfit, hsig, hslope)) {
         txt += StringFormat(" | %s %s/%s", HTFName(), Sgn(hzr, 1), Sgn(hzs, 1));
         tip += StringFormat("\n① %s: Z_reg %s / Z_SMA %s | ความชัน %s σ/แท่ง", HTFName(), Sgn(hzr, 2), Sgn(hzs, 2), Sgn(hslope / hsig, 2));
      }
      // ② VWAP (ผลรวมถึงแท่งก่อนหน้าของวันเดียวกัน)
      if(DayStart(time[e]) == DayStart(time[i]) && cVv[e] > 0.0) {
         double vw = cV1[e] / cVv[e], vr = cV2[e] / cVv[e] - vw * vw, vsd = (vr > 0.0) ? MathSqrt(vr) : 0.0;
         if(vsd > 0.0) {
            txt += " | VW " + Sgn((price - vw) / vsd, 1) + "σ";
            tip += StringFormat("\n② VWAP %s (σ %s): ห่าง %s σ", DoubleToString(vw, _Digits), DoubleToString(vsd, _Digits), Sgn((price - vw) / vsd, 2));
         }
      }
      if(atr > 0.0) {
         // ③ Keltner / ⑥ EMA ยาว / ④ วันก่อน (หน่วย ATR ของแท่งก่อนหน้า)
         double kc = (price - bKcMid[e]) / atr, el = (price - bEmaL[e]) / atr;
         bool   sq = (cSqz[e] > 0.0 && cSqz[e] < 1.0);
         txt += " | KC " + Sgn(kc, 1) + (sq ? "🔒" : "") + " | E" + IntegerToString(InpEMALong) + " " + Sgn(el, 1);
         tip += StringFormat("\n③ Keltner: ห่าง EMA%d %s ATR | BB/KC %.2f%s\n⑥ EMA%d: ห่าง %s ATR",
                             InpKC_Period, Sgn(kc, 2), cSqz[e], (sq ? " (Squeeze)" : ""), InpEMALong, Sgn(el, 2));
         double pd = (side == 0) ? bPdh[i] : bPdl[i];
         if(pd != EMPTY_VALUE) {
            string pn = (side == 0) ? "PDH" : "PDL";
            txt += " | " + pn + " " + Sgn((price - pd) / atr, 1);
            tip += StringFormat("\n④ %s %s: ห่าง %s ATR | Close วันก่อน %s", pn, DoubleToString(pd, _Digits), Sgn((price - pd) / atr, 2),
                                (bPdc[i] != EMPTY_VALUE ? DoubleToString(bPdc[i], _Digits) : "-"));
         }
         tip += StringFormat(" | เลขกลม $%.0f ห่าง %s", InpRoundStep, DoubleToString(price - MathRound(price / InpRoundStep) * InpRoundStep, 2));
      }
      // ⑤ พัดเส้น 7 เส้น
      double fw;
      int    fo;
      if(FanAt(close, e, fw, fo)) {
         txt += StringFormat(" | พัด %.1f %+d", fw, fo);
         tip += StringFormat("\n⑤ พัดเส้น 7 เส้น: กว้าง %.2f × SD20 | ลำดับ %+d (+6 เรียงขึ้นครบ … −6 เรียงลงครบ)", fw, fo);
      }
      tip += "\n(ค่าของเส้นใช้แท่งก่อนหน้า ยกเว้น TF ใหญ่ = แท่งที่ปิดแล้ว + ราคาสุดขั้วนี้; KC / EMA / PD หน่วย ATR)";

      double y = (side == 0) ? price + PtsToPrice(InpLabelOffset_Pts) : price - PtsToPrice(InpLabelOffset_Pts);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, time[i], y);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpLabelFontSize);
         ObjectSetDouble(0,  name, OBJPROP_ANGLE, 90.0);   // ตั้งขึ้น ไม่ทับป้ายของแท่งข้าง ๆ
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_LEFT : ANCHOR_RIGHT);
         ObjectSetInteger(0, name, OBJPROP_COLOR, (side == 0) ? InpClrLabelSell : InpClrLabelBuy);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetDouble(0, name, OBJPROP_PRICE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
   }
}

//====================================================================
// ④ เลขกลม (เส้นแนวนอนรอบราคาปัจจุบัน วาดใหม่เมื่อราคาเปลี่ยนช่วง)
//====================================================================
void DrawRound(double price) {
   if(!InpShowRound || price <= 0.0) return;
   double mid = MathRound(price / InpRoundStep) * InpRoundStep;
   if(mid == g_rn_mid) return;
   g_rn_mid = mid;
   ObjectsDeleteAll(0, PFX + "RN_");
   for(int k = -InpRoundCount; k <= InpRoundCount; k++) {
      double lvl   = mid + k * InpRoundStep;
      double q     = lvl / InpRoundMajor;
      bool   major = (MathAbs(q - MathRound(q)) < 1e-6);
      string nm    = PFX + "RN_" + DoubleToString(lvl, 2);
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, lvl);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, major ? InpClrRoundMajor : InpClrRound);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, major ? STYLE_SOLID : STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP, (major ? "เลขกลมหลัก " : "เลขกลม ") + DoubleToString(lvl, 2));
   }
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
void SetPlot(int plot, bool show, color clr, int begin) {
   if(!show) PlotIndexSetInteger(plot, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(plot, PLOT_LINE_COLOR, 0, clr);
   PlotIndexSetInteger(plot, PLOT_DRAW_BEGIN, begin);
   PlotIndexSetDouble(plot, PLOT_EMPTY_VALUE, EMPTY_VALUE);
}

int OnInit() {
   if(InpZ_Period < 3 || InpKC_Period < 2 || InpFastPeriod < 2 || InpEMALong < 2 || InpKC_Mult <= 0.0 || InpSqueezeBB_Mult <= 0.0 ||
      InpLabelZ <= 0.0 || InpHTFBandZ <= 0.0 || InpRoundStep <= 0.0 || InpRoundMajor < InpRoundStep || InpRoundCount < 0 || InpLabelBars < 0) {
      Print("❌ ค่า Input ไม่ถูกต้อง (Period ≥ 2-3, ตัวคูณ / เกณฑ์ > 0, เลขกลมหลัก ≥ ระยะเลขกลม)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   InitALMAWeights(InpFastPeriod);
   g_warm = MathMax(MathMax(3 * InpKC_Period, InpEMALong), MathMax(2 * InpFastPeriod + 5, InpZ_Period + 5));

   SetIndexBuffer(0,  bKcMid, INDICATOR_DATA);
   SetIndexBuffer(1,  bKcUp,  INDICATOR_DATA);
   SetIndexBuffer(2,  bKcUpC, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(3,  bKcLo,  INDICATOR_DATA);
   SetIndexBuffer(4,  bKcLoC, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5,  bEmaL,  INDICATOR_DATA);
   SetIndexBuffer(6,  bVw,    INDICATOR_DATA);
   SetIndexBuffer(7,  bVwP1,  INDICATOR_DATA);
   SetIndexBuffer(8,  bVwM1,  INDICATOR_DATA);
   SetIndexBuffer(9,  bVwP2,  INDICATOR_DATA);
   SetIndexBuffer(10, bVwM2,  INDICATOR_DATA);
   SetIndexBuffer(11, bHc,    INDICATOR_DATA);
   SetIndexBuffer(12, bHp,    INDICATOR_DATA);
   SetIndexBuffer(13, bHm,    INDICATOR_DATA);
   SetIndexBuffer(14, bPdh,   INDICATOR_DATA);
   SetIndexBuffer(15, bPdl,   INDICATOR_DATA);
   SetIndexBuffer(16, bPdc,   INDICATOR_DATA);
   SetIndexBuffer(17, cAtr,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(18, cVv,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(19, cV1,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(20, cV2,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(21, cDayH,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(22, cDayL,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(23, cEmaF,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(24, cSqz,   INDICATOR_CALCULATIONS);

   int kc_begin = 3 * InpKC_Period;
   SetPlot(0,  InpShowKeltner, InpClrKeltner,  kc_begin);
   SetPlot(1,  InpShowKeltner, InpClrKeltner,  kc_begin);
   SetPlot(2,  InpShowKeltner, InpClrKeltner,  kc_begin);
   PlotIndexSetInteger(1, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(2, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, InpClrSqueeze);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 1, InpClrSqueeze);
   SetPlot(3,  InpShowEMALong, InpClrEMALong,  InpEMALong);
   SetPlot(4,  InpShowVWAP,    InpClrVWAP,     0);
   for(int p = 5; p <= 8; p++)  SetPlot(p, InpShowVWAP,    InpClrVWAPBand, 0);
   for(int p = 9; p <= 11; p++) SetPlot(p, InpShowHTF,     InpClrHTF,      0);
   for(int p = 12; p <= 14; p++) SetPlot(p, InpShowPrevDay, InpClrPrevDay,  0);

   IndicatorSetString(INDICATOR_SHORTNAME, "7L Context");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   g_h_bar  = 0;
   g_h_fail = 0;
   g_rn_mid = 0.0;
   ArrayResize(g_h, 0);
   ArrayResize(g_hc, 0);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, PFX);
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
   if(rates_total < g_warm + 5) return(0);

   // TF ใหญ่: ครั้งแรกยังโหลดไม่ได้ → ลองใหม่ Tick หน้า (สูงสุด 30 ครั้ง แล้ววาดต่อโดยไม่มีเส้น TF ใหญ่)
   //   ระหว่างทำงานโหลดใหม่ไม่ได้ → ใช้ชุดเดิมไปก่อน (แท่งปัจจุบันถูกคำนวณใหม่ทุก Tick อยู่แล้ว)
   if(LoadHTF(time[0])) g_h_fail = 0;
   else if(prev_calculated == 0 && ++g_h_fail <= 30) return(0);

   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(start == 0) { ObjectsDeleteAll(0, PFX + "LS_"); ObjectsDeleteAll(0, PFX + "LB_"); }

   int    n   = InpZ_Period, kp = InpKC_Period;
   double a_k = 2.0 / (kp + 1.0), a_l = 2.0 / (InpEMALong + 1.0), a_f = 2.0 / (InpFastPeriod + 1.0);
   for(int i = start; i < rates_total; i++) {
      double c = close[i];
      bool   newday = (i == 0 || DayStart(time[i]) != DayStart(time[i - 1]));

      // ③ Keltner / ⑥ EMA ยาว / EMA เร็ว (พัด)
      if(i == 0) { bKcMid[i] = c; cAtr[i] = high[i] - low[i]; bEmaL[i] = c; cEmaF[i] = c; }
      else {
         double tr = MathMax(high[i], close[i - 1]) - MathMin(low[i], close[i - 1]);
         bKcMid[i] = c * a_k + bKcMid[i - 1] * (1.0 - a_k);
         cAtr[i]   = (cAtr[i - 1] * (kp - 1) + tr) / kp;   // Wilder
         bEmaL[i]  = c * a_l + bEmaL[i - 1] * (1.0 - a_l);
         cEmaF[i]  = c * a_f + cEmaF[i - 1] * (1.0 - a_f);
      }
      bKcUp[i] = bKcMid[i] + InpKC_Mult * cAtr[i];
      bKcLo[i] = bKcMid[i] - InpKC_Mult * cAtr[i];
      cSqz[i]  = (i >= n - 1 && cAtr[i] > 0.0) ? (InpSqueezeBB_Mult * SDAt(close, i, n)) / (InpKC_Mult * cAtr[i]) : 0.0;
      bKcUpC[i] = (cSqz[i] > 0.0 && cSqz[i] < 1.0) ? 1.0 : 0.0;
      bKcLoC[i] = bKcUpC[i];

      // ② VWAP รายวัน (รวมแท่งนี้)
      double tp = (high[i] + low[i] + c) / 3.0, v = (double)tick_volume[i];
      cVv[i] = (newday ? 0.0 : cVv[i - 1]) + v;
      cV1[i] = (newday ? 0.0 : cV1[i - 1]) + v * tp;
      cV2[i] = (newday ? 0.0 : cV2[i - 1]) + v * tp * tp;
      if(cVv[i] > 0.0) {
         double vw = cV1[i] / cVv[i], vr = cV2[i] / cVv[i] - vw * vw, vsd = (vr > 0.0) ? MathSqrt(vr) : 0.0;
         bVw[i] = vw; bVwP1[i] = vw + vsd; bVwM1[i] = vw - vsd; bVwP2[i] = vw + 2.0 * vsd; bVwM2[i] = vw - 2.0 * vsd;
      }
      else { bVw[i] = EMPTY_VALUE; bVwP1[i] = EMPTY_VALUE; bVwM1[i] = EMPTY_VALUE; bVwP2[i] = EMPTY_VALUE; bVwM2[i] = EMPTY_VALUE; }

      // ④ High / Low / Close วันก่อน (วันแรกของกราฟไม่ครบวัน → ไม่ใช้)
      cDayH[i] = newday ? high[i] : MathMax(cDayH[i - 1], high[i]);
      cDayL[i] = newday ? low[i]  : MathMin(cDayL[i - 1], low[i]);
      if(newday) {
         bool full = (i > 0 && DayStart(time[i - 1]) != DayStart(time[0]));
         bPdh[i] = full ? cDayH[i - 1] : EMPTY_VALUE;
         bPdl[i] = full ? cDayL[i - 1] : EMPTY_VALUE;
         bPdc[i] = full ? close[i - 1] : EMPTY_VALUE;
      }
      else { bPdh[i] = bPdh[i - 1]; bPdl[i] = bPdl[i - 1]; bPdc[i] = bPdc[i - 1]; }

      // ① TF ใหญ่: แท่งที่ปิดแล้ว ณ ต้นแท่งนี้ + ราคาปิดของแท่งนี้
      bHc[i] = EMPTY_VALUE; bHp[i] = EMPTY_VALUE; bHm[i] = EMPTY_VALUE;
      int hk = (ArraySize(g_hc) > 0) ? HTFIdx(time[i]) : -1;
      double zr, zs, fit, sig, slope;
      if(hk >= 0 && ZAt(g_hc, hk, c, zr, zs, fit, sig, slope)) {
         bHc[i] = fit;
         bHp[i] = fit + InpHTFBandZ * sig;
         bHm[i] = fit - InpHTFBandZ * sig;
      }
   }

   // 🏷️ ป้าย (แท่งปัจจุบันประเมินใหม่ทุก Tick)
   if(InpShowLabels) {
      int from = (InpLabelBars > 0) ? MathMax(1, rates_total - InpLabelBars) : 1;
      for(int i = MathMax(start, from); i < rates_total; i++) LabelBar(i, time, high, low, close);
   }
   DrawRound(close[rates_total - 1]);
   return(rates_total);
}
//+------------------------------------------------------------------+
