package com.functionhx.writebench;

import android.app.*;
import android.content.*;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import android.text.*;
import android.view.*;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.TextRecognition;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

public final class MainActivity extends Activity {
  static final int BLUE = 0xff3266f5,
      INK = 0xff17233c,
      MUTED = 0xff73819b,
      CANVAS = 0xfff4f7fc,
      LINE = 0xffe3eaf5;
  private LinearLayout root, body;
  private TextView clock;
  private EditText editor, questionEditor;
  private ExamTask task = ExamTask.KA_SMALL;
  private String question = task.prompt(), essay = "", apiKey = "", page = "write", rewriteID = "";
  private boolean answering = false, grading = false, handwritten = false;
  private long elapsed = 0, started = 0;
  private LocalStore store;
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private GradingEngine engine;
  private Future<?> operation;
  private JSONObject review;
  private final ArrayList<Uri> images = new ArrayList<>();
  private final ArrayList<String> recognized = new ArrayList<>();
  private int ocrPurpose = 0, ocrIndex = 0;
  private boolean inOCR = false, recognizing = false;
  private final Runnable ticker =
      new Runnable() {
        public void run() {
          if (clock != null && answering) clock.setText(timeText());
          if (answering && currentElapsed() / 1000 % 5 == 0) saveDraft();
          handler.postDelayed(this, 1000);
        }
      };

  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    store = new LocalStore(this);
    try {
      task = ExamTask.valueOf(getPreferences(0).getString("task", task.name()));
      loadDraft();
    } catch (Exception e) {
      message("无法读取草稿", e.getMessage());
    }
    render();
    handler.post(ticker);
  }

  private int dp(float n) {
    return Math.round(n * getResources().getDisplayMetrics().density);
  }

  private GradientDrawable shape(int color, int radius) {
    var d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    d.setStroke(dp(1), LINE);
    return d;
  }

  private TextView text(String s, int size, int color) {
    TextView v = new TextView(this);
    v.setText(s);
    v.setTextSize(size);
    v.setTextColor(color);
    v.setLineSpacing(dp(4), 1);
    return v;
  }

  private TextView label(String s) {
    TextView v = text(s, 13, MUTED);
    v.setPadding(0, dp(8), 0, dp(8));
    return v;
  }

  private Button button(String s, boolean primary, Runnable action) {
    Button b = new Button(this);
    b.setText(s);
    b.setAllCaps(false);
    b.setTextSize(14);
    b.setTextColor(primary ? Color.WHITE : BLUE);
    b.setMinHeight(dp(48));
    b.setBackground(
        new RippleDrawable(
            ColorStateList.valueOf(0x223266f5), shape(primary ? BLUE : Color.WHITE, 14), null));
    b.setPadding(dp(18), dp(10), dp(18), dp(10));
    b.setOnClickListener(v -> action.run());
    return b;
  }

  private LinearLayout column() {
    LinearLayout l = new LinearLayout(this);
    l.setOrientation(1);
    return l;
  }

  private LinearLayout row() {
    LinearLayout l = new LinearLayout(this);
    l.setOrientation(0);
    l.setGravity(Gravity.CENTER_VERTICAL);
    return l;
  }

  private void gap(LinearLayout p, int height) {
    Space s = new Space(this);
    p.addView(s, new LinearLayout.LayoutParams(1, dp(height)));
  }

  private void addButton(LinearLayout p, String s, boolean primary, Runnable action) {
    p.addView(button(s, primary, action), new LinearLayout.LayoutParams(-1, dp(50)));
    gap(p, 12);
  }

  private LinearLayout card(LinearLayout p) {
    LinearLayout c = column();
    c.setPadding(dp(20), dp(18), dp(20), dp(18));
    c.setBackground(shape(Color.WHITE, 20));
    p.addView(c, new LinearLayout.LayoutParams(-1, -2));
    gap(p, 16);
    return c;
  }

  private void title(LinearLayout p, String h, String sub) {
    TextView t = text(h, 28, INK);
    t.setTypeface(null, Typeface.BOLD);
    p.addView(t);
    p.addView(label(sub));
    gap(p, 18);
  }

  private EditText input(String value, String hint, int minLines) {
    EditText e = new EditText(this);
    e.setText(value);
    e.setHint(hint);
    e.setTextSize(16);
    e.setTextColor(INK);
    e.setHintTextColor(MUTED);
    e.setGravity(Gravity.TOP);
    e.setPadding(dp(12), dp(12), dp(12), dp(12));
    e.setBackground(shape(CANVAS, 12));
    e.setMinLines(minLines);
    e.setInputType(
        android.text.InputType.TYPE_CLASS_TEXT
            | android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
            | android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
    return e;
  }

  private void watch(EditText e, java.util.function.Consumer<String> action) {
    e.addTextChangedListener(
        new TextWatcher() {
          public void beforeTextChanged(CharSequence s, int a, int c, int f) {}

          public void onTextChanged(CharSequence s, int a, int before, int count) {
            action.accept(s.toString());
          }

          public void afterTextChanged(Editable x) {}
        });
  }

  private void render() {
    if (isDestroyed()) return;
    root = column();
    root.setFocusableInTouchMode(true);
    root.setBackgroundColor(CANVAS);
    root.setPadding(dp(20), dp(12), dp(20), 0);
    setContentView(root);
    root.setOnApplyWindowInsetsListener(
        (v, insets) -> {
          root.setPadding(
              dp(20),
              insets.getSystemWindowInsetTop() + dp(12),
              dp(20),
              Math.max(
                  insets.getInsets(WindowInsets.Type.systemBars()).bottom,
                  insets.getInsets(WindowInsets.Type.ime()).bottom));
          return insets;
        });
    if (Build.VERSION.SDK_INT >= 30) {
      getWindow().getInsetsController().show(WindowInsets.Type.systemBars());
      if (answering) getWindow().getInsetsController().hide(WindowInsets.Type.statusBars());
    }
    LinearLayout head = row();
    TextView brand = text(answering ? task.title() : "WriteBench", 18, INK);
    brand.setTypeface(null, Typeface.BOLD);
    head.addView(brand, new LinearLayout.LayoutParams(0, dp(44), 1));
    if (answering) {
      clock = text(timeText(), 14, BLUE);
      clock.setGravity(Gravity.CENTER);
      head.addView(clock);
    }
    root.addView(head);
    gap(root, 12);
    if (answering) {
      answerUI();
      return;
    }
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    scroll.setClipToPadding(false);
    body = column();
    body.setPadding(0, dp(10), 0, dp(22));
    scroll.addView(body);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    switch (page) {
      case "history" -> historyUI();
      case "mistakes" -> mistakesUI();
      case "settings" -> settingsUI();
      case "review" -> reviewUI();
      default -> homeUI();
    }
    LinearLayout nav = row();
    String[] names = {"写作", "历史", "错题", "设置"}, ids = {"write", "history", "mistakes", "settings"};
    for (int i = 0; i < names.length; i++) {
      final String dest = ids[i];
      Button b =
          button(
              names[i],
              false,
              () -> {
                page = dest;
                render();
              });
      b.setTextColor(page.equals(dest) ? BLUE : MUTED);
      b.setBackgroundColor(Color.TRANSPARENT);
      nav.addView(b, new LinearLayout.LayoutParams(0, dp(56), 1));
    }
    root.addView(nav);
  }

  private void homeUI() {
    title(body, task.isTranslation() ? "准备翻译" : "准备写作", "选好题目，专注完成一次练习。");
    String[] names = {"考研英语", "CET-6 六级", "IELTS 雅思"};
    String[] details = {"英语一写作 · 英语一 / 二翻译", "写作 · 汉译英", "Academic · Task 1 / Task 2"};
    for (int i = 0; i < 3; i++) {
      final int kind = i;
      LinearLayout c = row();
      c.setPadding(dp(16), dp(13), dp(16), dp(13));
      boolean selected = task.group() == i;
      c.setBackground(shape(selected ? 0xffedf3ff : Color.WHITE, 18));
      c.addView(new ExamIcon(this, i), new LinearLayout.LayoutParams(dp(35), dp(35)));
      LinearLayout words = column();
      words.setPadding(dp(16), 0, 0, 0);
      TextView n = text(names[i], 16, INK);
      n.setTypeface(null, Typeface.BOLD);
      words.addView(n);
      words.addView(text(details[i], 12, MUTED));
      c.addView(words, new LinearLayout.LayoutParams(0, -2, 1));
      c.addView(text(selected ? "●" : "›", 20, selected ? BLUE : MUTED));
      c.setOnClickListener(
          v ->
              selectTask(
                  kind == 0 ? ExamTask.KA_SMALL : kind == 1 ? ExamTask.CET6 : ExamTask.IELTS1));
      body.addView(c);
      gap(body, 10);
    }
    HorizontalScrollView subScroll = new HorizontalScrollView(this);
    subScroll.setHorizontalScrollBarEnabled(false);
    LinearLayout sub = row();
    for (ExamTask option : ExamTask.values())
      if (option.exam.equals(task.exam)) {
        Button b = button(option.subtype, option == task, () -> selectTask(option));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, dp(46));
        lp.setMargins(dp(3), 0, dp(3), 0);
        sub.addView(b, lp);
      }
    subScroll.addView(sub);
    body.addView(subScroll);
    gap(body, 22);
    LinearLayout card = card(body);
    card.addView(label("题目 · 原创练习 / 自行导入"));
    questionEditor = input(question, "输入或粘贴题目", 5);
    card.addView(questionEditor);
    watch(
        questionEditor,
        s -> {
          question = s;
          rewriteID = "";
          saveDraft();
        });
    gap(card, 12);
    addButton(card, "从图片识别题目", false, () -> importImages(0));
    addButton(
        root,
        essay.isBlank() ? "开始答题  →" : "继续答题  →",
        true,
        () -> {
          if (question.isBlank()) {
            message("请先填写题目", "");
            return;
          }
          saveDraft();
          answering = true;
          started = System.currentTimeMillis();
          render();
        });
    body.addView(label("开始后进入沉浸式答题 · 草稿保存在本机"));
  }

  private void answerUI() {
    LinearLayout actions = row();
    actions.addView(
        button("保存并离开", false, () -> leaveAnswer()), new LinearLayout.LayoutParams(0, dp(46), 1));
    Space sp = new Space(this);
    actions.addView(sp, new LinearLayout.LayoutParams(dp(12), 1));
    Button handIn = button(grading ? "评审中…" : "交卷", true, this::submit);
    handIn.setEnabled(!grading);
    actions.addView(handIn, new LinearLayout.LayoutParams(0, dp(46), 1));
    root.addView(actions);
    gap(root, 12);
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    LinearLayout paper = column();
    LinearLayout prompt = card(paper);
    prompt.addView(label("试题"));
    TextView q = text(question, 15, INK);
    q.setTextIsSelectable(true);
    prompt.addView(q);
    LinearLayout answer = card(paper);
    answer.addView(label(task.showCount() ? "作答区 · IELTS" : "答题区"));
    editor = new RuledEditor(this, !task.showCount());
    editor.setText(essay);
    editor.setEnabled(!grading);
    answer.addView(editor, new LinearLayout.LayoutParams(-1, dp(360)));
    watch(
        editor,
        s -> {
          essay = s;
          saveDraft();
        });
    if (task.showCount()) {
      TextView count = label("Words: " + wordCount(essay));
      answer.addView(count);
      watch(editor, s -> count.setText("Words: " + wordCount(s)));
    }
    scroll.addView(paper);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    if (grading) {
      TextView progress = label("三位独立评审 · DeepSeek V4 Pro / MAX\n可能需要数分钟，全部完成后才生成总分。");
      root.addView(progress);
      addButton(
          root,
          "取消评卷",
          false,
          () -> {
            if (engine != null) engine.cancel();
            if (operation != null) operation.cancel(true);
            grading = false;
            started = System.currentTimeMillis();
            render();
          });
    } else {
      Button imp = button("导入手写稿", false, () -> importImages(1));
      root.addView(imp, new LinearLayout.LayoutParams(-1, dp(46)));
      root.addView(label("草稿自动保存 · 先校对图片识别结果，再提交"));
    }
  }

  private void leaveAnswer() {
    if (grading) return;
    elapsed = currentElapsed();
    answering = false;
    saveDraft();
    render();
  }

  private long currentElapsed() {
    return elapsed
        + (answering && !grading ? Math.max(0, System.currentTimeMillis() - started) : 0);
  }

  private String timeText() {
    long seconds = currentElapsed() / 1000;
    return String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60);
  }

  static int wordCount(String s) {
    return s.isBlank() ? 0 : s.trim().split("\\s+").length;
  }

  private void selectTask(ExamTask next) {
    saveDraft();
    task = next;
    getPreferences(0).edit().putString("task", task.name()).apply();
    try {
      loadDraft();
    } catch (Exception e) {
      message("无法读取草稿", e.getMessage());
    }
    render();
  }

  private void loadDraft() throws Exception {
    JSONObject d = store.read("draft-" + task.name() + ".json");
    question = d.optString("question", task.prompt());
    essay = d.optString("essay", "");
    elapsed = d.optLong("elapsed", 0);
    handwritten = d.optBoolean("handwritten", false);
    rewriteID = d.optString("rewriteID", "");
  }

  private void saveDraft() {
    if (store == null) return;
    try {
      store.write(
          "draft-" + task.name() + ".json",
          new JSONObject()
              .put("question", question)
              .put("essay", essay)
              .put("elapsed", currentElapsed())
              .put("handwritten", handwritten)
              .put("rewriteID", rewriteID));
      if (!rewriteID.isBlank()) store.rewrite(rewriteID, essay);
    } catch (Exception e) {
      if (!isFinishing()) Toast.makeText(this, "草稿保存失败，请检查存储空间", Toast.LENGTH_SHORT).show();
    }
  }

  private void settingsUI() {
    title(body, "你的写作工作台", "AI 设置 · 简单直接");
    LinearLayout c = card(body);
    TextView t = text("DeepSeek API", 20, INK);
    t.setTypeface(null, Typeface.BOLD);
    c.addView(t);
    c.addView(label("三位独立评审 · DeepSeek V4 Pro · MAX"));
    EditText key = input("", "填入你的 DeepSeek API Key", 1);
    key.setInputType(129);
    c.addView(key);
    gap(c, 16);
    addButton(
        c,
        "使用此 Key",
        true,
        () -> {
          String value = key.getText().toString().trim();
          if (value.isEmpty()) {
            message("请输入 API Key", "");
            return;
          }
          apiKey = value;
          key.setText("");
          render();
          message("Key 已启用", "仅保留在本次运行内存中，关闭应用后请重新填写。现在可以开始答题并提交。");
        });
    c.addView(label(apiKey.isBlank() ? "尚未填写 Key" : "Key 已启用 · 本次运行有效"));
    LinearLayout info = card(body);
    info.addView(text("适合手机的独立练习", 18, INK));
    info.addView(label("Android 版直接使用你填写的 API Key，不连接电脑上的 Codex，也不保存任何 ChatGPT 凭据。"));
    info.addView(label("图片识别在本机完成；只有校对确认的题目与作文会发送给评审服务。草稿和历史保存在应用私有存储。"));
    body.addView(label("WriteBench Android 0.1.0 · Native preview"));
  }

  private void submit() {
    if (grading || !answering) return;
    saveDraft();
    if (apiKey.isBlank()) {
      new AlertDialog.Builder(this)
          .setTitle("未配置 DeepSeek API Key")
          .setMessage("作答已保存，本次未生成评分。请在设置中填入自己的 Key。")
          .setNegativeButton("继续作答", null)
          .setPositiveButton(
              "前往设置",
              (d, w) -> {
                leaveAnswer();
                page = "settings";
                render();
              })
          .show();
      return;
    }
    if (essay.isBlank()) {
      message("请先填写作答内容", "");
      return;
    }
    elapsed = currentElapsed();
    grading = true;
    ((InputMethodManager) getSystemService(INPUT_METHOD_SERVICE))
        .hideSoftInputFromWindow(root.getWindowToken(), 0);
    render();
    engine = new GradingEngine();
    final GradingEngine active = engine;
    final ExamTask submittedTask = task;
    final String submittedQuestion = question, submittedEssay = essay, submittedKey = apiKey;
    final long duration = elapsed;
    final boolean fromHandwriting = handwritten;
    operation =
        worker.submit(
            () -> {
              try {
                String rubric;
                try (var in = getAssets().open("rubrics/" + submittedTask.rubric + ".md")) {
                  rubric = new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
                }
                JSONObject result =
                    active.grade(
                        submittedTask, submittedQuestion, submittedEssay, rubric, submittedKey);
                JSONObject session =
                    new JSONObject()
                        .put("id", UUID.randomUUID().toString())
                        .put("date", System.currentTimeMillis())
                        .put("task", submittedTask.name())
                        .put("question", submittedQuestion)
                        .put("essay", submittedEssay)
                        .put("writingDuration", duration)
                        .put("wordCount", wordCount(submittedEssay))
                        .put("inputMode", fromHandwriting ? "handwritten" : "typed")
                        .put("finalRewrite", "")
                        .put(
                            "correctedEssay",
                            result
                                .getJSONArray("reviewers")
                                .getJSONObject(1)
                                .getJSONObject("response")
                                .getString("improvedVersion"))
                        .put("report", result);
                if (Thread.currentThread().isInterrupted()) return;
                store.add(session);
                runOnUiThread(
                    () -> {
                      if (engine != active || !grading || isDestroyed()) return;
                      grading = false;
                      answering = false;
                      review = session;
                      page = "review";
                      render();
                    });
              } catch (Exception e) {
                runOnUiThread(
                    () -> {
                      if (engine != active || !grading) return;
                      grading = false;
                      started = System.currentTimeMillis();
                      render();
                      message("评卷未完成", e.getMessage());
                    });
              }
            });
  }

  private void historyUI() {
    title(body, "写过的每一篇", "历史与练习统计");
    try {
      JSONArray records = store.history();
      double normalized = 0;
      for (int i = 0; i < records.length(); i++) {
        JSONObject s = records.getJSONObject(i);
        normalized +=
            s.getJSONObject("report").getDouble("finalScore")
                / ExamTask.valueOf(s.getString("task")).maximum;
      }
      LinearLayout summary = card(body);
      summary.addView(text(records.length() + " 篇练习", 26, INK));
      summary.addView(
          label(
              records.length() == 0
                  ? "完成首次评卷后，原稿和完整评阅会保存在这里。"
                  : "平均得分比例 "
                      + Math.round(normalized / records.length() * 100)
                      + "% · 不同题型按满分归一化"));
      for (int i = 0; i < records.length(); i++) {
        JSONObject s = records.getJSONObject(i), report = s.getJSONObject("report");
        ExamTask exam = ExamTask.valueOf(s.getString("task"));
        LinearLayout c = card(body);
        c.addView(text(exam.title(), 17, INK));
        c.addView(
            label(
                new SimpleDateFormat("yyyy.MM.dd  HH:mm", Locale.getDefault())
                    .format(new Date(s.getLong("date")))));
        c.addView(text(report.getDouble("finalScore") + " / " + exam.maximum, 28, BLUE));
        c.addView(label(report.getString("confidence") + " confidence"));
        addButton(
            c,
            "打开评阅",
            false,
            () -> {
              review = s;
              page = "review";
              render();
            });
      }
    } catch (Exception e) {
      message("历史读取失败", e.getMessage());
    }
  }

  private void reviewUI() {
    if (review == null) {
      page = "history";
      historyUI();
      return;
    }
    try {
      JSONObject report = review.getJSONObject("report");
      ExamTask exam = ExamTask.valueOf(review.getString("task"));
      title(body, exam.isTranslation() ? "这一次的翻译" : "这一次的写作", exam.title());
      LinearLayout score = card(body);
      score.addView(text(report.getDouble("finalScore") + " / " + exam.maximum, 44, BLUE));
      score.addView(label(report.getString("confidence") + " confidence · 三评中位数"));
      JSONArray reviewers = report.getJSONArray("reviewers");
      for (int i = 0; i < reviewers.length(); i++) {
        JSONObject j = reviewers.getJSONObject(i), r = j.getJSONObject("response");
        LinearLayout c = card(body);
        c.addView(text(j.getString("judge") + "     " + r.getDouble("score"), 21, INK));
        c.addView(label(j.getString("model") + " · MAX"));
        c.addView(text(r.getString("summary"), 15, INK));
        for (String field : List.of("majorErrors", "minorErrors")) {
          JSONArray errors = r.getJSONArray(field);
          for (int n = 0; n < errors.length(); n++) c.addView(label("• " + errors.getString(n)));
        }
      }
      LinearLayout diagnostics = card(body);
      String[] fields = {"taskCompletion", "language", "coherence", "register"},
          labels = {exam.isTranslation() ? "译义与完整性" : "任务完成", "语言表达", "连贯性", "语域"};
      for (int d = 0; d < fields.length; d++) {
        double value = 0;
        for (int j = 0; j < 3; j++)
          value += reviewers.getJSONObject(j).getJSONObject("response").getDouble(fields[d]) / 3;
        diagnostics.addView(
            label(labels[d] + "  " + String.format(Locale.ROOT, "%.1f / 10", value)));
        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(100);
        bar.setProgress((int) Math.round(value * 10));
        bar.setProgressTintList(ColorStateList.valueOf(BLUE));
        diagnostics.addView(bar, new LinearLayout.LayoutParams(-1, dp(5)));
        gap(diagnostics, 10);
      }
      LinearLayout original = card(body);
      addButton(
          original,
          "查看原题与原稿",
          false,
          () -> {
            try {
              message("原题与原稿", review.getString("question") + "\n\n" + review.getString("essay"));
            } catch (Exception e) {
              message("读取失败", e.getMessage());
            }
          });
      LinearLayout corrections = card(body);
      corrections.addView(text("值得改好的句子", 20, INK));
      HashSet<String> seen = new HashSet<>();
      for (int i = 0; i < reviewers.length(); i++) {
        JSONArray list =
            reviewers.getJSONObject(i).getJSONObject("response").getJSONArray("corrections");
        for (int j = 0; j < list.length(); j++) {
          JSONObject c = list.getJSONObject(j);
          if (!seen.add(c.getString("original"))) continue;
          corrections.addView(label(c.getString("category")));
          corrections.addView(text(c.getString("original"), 14, MUTED));
          corrections.addView(text("→ " + c.getString("corrected"), 15, INK));
          corrections.addView(label(c.getString("explanation")));
          gap(corrections, 12);
        }
      }
      if (seen.isEmpty()) corrections.addView(label("评审未标记逐句修改，请结合评语检查任务完成情况。"));
      LinearLayout version = card(body);
      version.addView(text(exam.isTranslation() ? "参考改译" : "改进版本", 20, INK));
      TextView improved =
          text(
              reviewers.getJSONObject(1).getJSONObject("response").getString("improvedVersion"),
              16,
              INK);
      improved.setTextIsSelectable(true);
      version.addView(improved);
      addButton(
          body,
          "开始重写 →",
          true,
          () -> {
            try {
              task = exam;
              question = review.getString("question");
              essay = review.optString("finalRewrite", review.getString("essay"));
              rewriteID = review.getString("id");
              elapsed = 0;
              answering = true;
              started = System.currentTimeMillis();
              handwritten = false;
              saveDraft();
              render();
            } catch (Exception e) {
              message("无法重写", e.getMessage());
            }
          });
    } catch (Exception e) {
      message("评阅读取失败", e.getMessage());
    }
  }

  private void mistakesUI() {
    title(body, "把错误变成经验", "来自已完成评阅的真实修改建议");
    try {
      TreeMap<String, ArrayList<JSONObject>> grouped = new TreeMap<>();
      JSONArray records = store.history();
      for (int i = 0; i < records.length(); i++) {
        JSONArray judges =
            records.getJSONObject(i).getJSONObject("report").getJSONArray("reviewers");
        HashSet<String> seen = new HashSet<>();
        for (int j = 0; j < judges.length(); j++) {
          JSONArray cs =
              judges.getJSONObject(j).getJSONObject("response").getJSONArray("corrections");
          for (int k = 0; k < cs.length(); k++) {
            JSONObject c = cs.getJSONObject(k);
            if (seen.add(c.getString("category") + c.getString("original")))
              grouped.computeIfAbsent(c.getString("category"), x -> new ArrayList<>()).add(c);
          }
        }
      }
      if (grouped.isEmpty()) body.addView(label("完成一次真实评卷后，重要修改会按类别整理在这里。"));
      for (var entry : grouped.entrySet()) {
        LinearLayout c = card(body);
        c.addView(text(entry.getKey() + "  " + entry.getValue().size(), 20, INK));
        for (JSONObject error : entry.getValue().subList(0, Math.min(5, entry.getValue().size()))) {
          c.addView(label(error.getString("original")));
          c.addView(text("→ " + error.getString("corrected"), 15, INK));
        }
      }
    } catch (Exception e) {
      message("无法读取错题", e.getMessage());
    }
  }

  private void importImages(int purpose) {
    if (recognizing) {
      message("正在识别", "请等待本次识别完成。");
      return;
    }
    ocrPurpose = purpose;
    Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    i.setType("image/*");
    i.addCategory(Intent.CATEGORY_OPENABLE);
    i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
    startActivityForResult(i, 70);
  }

  @Override
  protected void onActivityResult(int code, int result, Intent data) {
    super.onActivityResult(code, result, data);
    if (code != 70 || result != RESULT_OK || data == null) return;
    if (data.getClipData() != null && data.getClipData().getItemCount() > 12) {
      message("图片过多", "一次最多导入 12 页，请分批导入。");
      return;
    }
    images.clear();
    recognized.clear();
    if (data.getClipData() != null) {
      for (int i = 0; i < Math.min(12, data.getClipData().getItemCount()); i++)
        images.add(data.getClipData().getItemAt(i).getUri());
    } else if (data.getData() != null) images.add(data.getData());
    if (images.isEmpty()) return;
    Toast.makeText(this, "正在本机识别，请稍候…", Toast.LENGTH_LONG).show();
    recognizing = true;
    recognizeNext(0);
  }

  private void recognizeNext(int index) {
    if (isDestroyed() || isFinishing()) {
      recognizing = false;
      return;
    }
    if (index >= images.size()) {
      recognizing = false;
      ocrIndex = 0;
      inOCR = true;
      showOCR();
      return;
    }
    try {
      Bitmap bitmap = scaledImage(images.get(index), 3200);
      InputImage image = InputImage.fromBitmap(bitmap, 0);
      var recognizer =
          TextRecognition.getClient(
              new com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions.Builder()
                  .build());
      recognizer
          .process(image)
          .addOnSuccessListener(
              result -> {
                recognized.add(result.getText());
                bitmap.recycle();
                recognizer.close();
                recognizeNext(index + 1);
              })
          .addOnFailureListener(
              error -> {
                recognizer.close();
                bitmap.recycle();
                recognizing = false;
                message("识别失败", error.getMessage());
              });
    } catch (Exception e) {
      recognizing = false;
      message("无法打开图片", e.getMessage());
    }
  }

  private Bitmap scaledImage(Uri uri, int maximum) throws java.io.IOException {
    try (var cursor =
        getContentResolver().query(uri, new String[] {OpenableColumns.SIZE}, null, null, null)) {
      if (cursor != null
          && cursor.moveToFirst()
          && !cursor.isNull(0)
          && cursor.getLong(0) > 25L * 1024 * 1024)
        throw new java.io.IOException("单页图片不能超过 25 MB，请缩小后导入。");
    }
    return ImageDecoder.decodeBitmap(
        ImageDecoder.createSource(getContentResolver(), uri),
        (decoder, info, source) -> {
          decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
          double scale =
              Math.min(
                  1.0,
                  (double) maximum
                      / Math.max(info.getSize().getWidth(), info.getSize().getHeight()));
          decoder.setTargetSize(
              Math.max(1, (int) (info.getSize().getWidth() * scale)),
              Math.max(1, (int) (info.getSize().getHeight() * scale)));
        });
  }

  private void showOCR() {
    LinearLayout sheet = column();
    sheet.setPadding(dp(18), dp(12), dp(18), dp(12));
    ScrollView scroll = new ScrollView(this);
    scroll.addView(sheet);
    TextView pageLabel = text("校对第 " + (ocrIndex + 1) + " / " + images.size() + " 页", 18, INK);
    sheet.addView(pageLabel);
    ImageView image = new ImageView(this);
    try {
      image.setImageBitmap(scaledImage(images.get(ocrIndex), 1600));
    } catch (Exception e) {
      message("预览失败", e.getMessage());
      return;
    }
    image.setScaleType(ImageView.ScaleType.FIT_CENTER);
    sheet.addView(image, new LinearLayout.LayoutParams(-1, dp(200)));
    EditText words = input(recognized.get(ocrIndex), "校正识别文字", 7);
    sheet.addView(words);
    watch(words, s -> recognized.set(ocrIndex, s));
    sheet.addView(label("识别错误不会自动进入评分。请对照原图逐页校正。"));
    CheckBox checked = new CheckBox(this);
    checked.setText("我已核对所有页面的文字");
    sheet.addView(checked);
    AlertDialog dialog =
        new AlertDialog.Builder(this)
            .setView(scroll)
            .setNegativeButton("取消", (d, w) -> inOCR = false)
            .setPositiveButton(ocrPurpose == 0 ? "确认填入题目" : "确认并评卷", null)
            .setNeutralButton(images.size() > 1 ? "下一页" : "查看原图", null)
            .create();
    dialog.setOnShowListener(
        d -> {
          Button confirm = dialog.getButton(-1);
          confirm.setEnabled(false);
          checked.setOnCheckedChangeListener((b, on) -> confirm.setEnabled(on));
          confirm.setOnClickListener(
              v -> {
                String combined = String.join("\n\n", recognized);
                if (ocrPurpose == 0) question = combined;
                else {
                  essay = combined;
                  handwritten = true;
                }
                inOCR = false;
                saveDraft();
                dialog.dismiss();
                render();
                if (ocrPurpose == 1) submit();
              });
          dialog
              .getButton(-3)
              .setOnClickListener(
                  v -> {
                    if (images.size() > 1) {
                      ocrIndex = (ocrIndex + 1) % images.size();
                      dialog.dismiss();
                      showOCR();
                    }
                  });
        });
    dialog.show();
  }

  private void message(String title, String detail) {
    if (isFinishing() || isDestroyed()) return;
    new AlertDialog.Builder(this)
        .setTitle(title)
        .setMessage(detail == null ? "" : detail)
        .setPositiveButton("知道了", null)
        .show();
  }

  @Override
  public void onBackPressed() {
    if (answering) {
      if (grading) {
        message("评审进行中", "请点击取消评卷，或等待三位评审完成。");
        return;
      }
      leaveAnswer();
    } else if (!page.equals("write")) {
      page = "write";
      render();
    } else super.onBackPressed();
  }

  @Override
  public void onConfigurationChanged(android.content.res.Configuration config) {
    super.onConfigurationChanged(config);
    saveDraft();
    render();
  }

  @Override
  protected void onPause() {
    super.onPause();
    saveDraft();
  }

  @Override
  protected void onDestroy() {
    handler.removeCallbacks(ticker);
    if (engine != null) engine.cancel();
    if (operation != null) operation.cancel(true);
    worker.shutdownNow();
    apiKey = "";
    super.onDestroy();
  }

  private static final class RuledEditor extends EditText {
    final boolean ruled;
    final Paint line = new Paint(3);

    RuledEditor(Context c, boolean ruled) {
      super(c);
      this.ruled = ruled;
      setTextSize(18);
      setTextColor(INK);
      setHintTextColor(MUTED);
      setHint("在这里开始作答…");
      setGravity(Gravity.TOP);
      setPadding(0, 12, 0, 12);
      setBackgroundColor(Color.TRANSPARENT);
      setLineSpacing(12, 1);
      setInputType(0x000a0001);
      line.setColor(LINE);
    }

    @Override
    protected void onDraw(Canvas c) {
      if (ruled) {
        int h = getLineHeight();
        int base = getBaseline() + 5;
        for (int y = base; y < getHeight() + getScrollY(); y += h)
          c.drawLine(0, y, getWidth(), y, line);
      }
      super.onDraw(c);
    }
  }
}
