package com.functionhx.writebench;

public enum ExamTask {
  KA_SMALL("考研英语", "小作文", 10, "kaoyan_english1_small"),
  KA_LARGE("考研英语", "大作文", 20, "kaoyan_english1_large"),
  KA_TRANSLATION("考研英语", "英语一翻译", 10, "kaoyan_english1_translation"),
  KA2_TRANSLATION("考研英语", "英语二翻译", 15, "kaoyan_english2_translation"),
  CET_TRANSLATION("CET-6 六级", "翻译", 15, "cet6_translation"),
  CET6("CET-6 六级", "Writing", 15, "cet6_writing"),
  IELTS1("IELTS 雅思", "Task 1", 9, "ielts_task1"),
  IELTS2("IELTS 雅思", "Task 2", 9, "ielts_task2");
  public final String exam, subtype, rubric;
  public final int maximum;

  ExamTask(String exam, String subtype, int maximum, String rubric) {
    this.exam = exam;
    this.subtype = subtype;
    this.maximum = maximum;
    this.rubric = rubric;
  }

  public boolean isTranslation() {
    return this == KA_TRANSLATION || this == KA2_TRANSLATION || this == CET_TRANSLATION;
  }

  public String targetLanguage() {
    return this == KA_TRANSLATION || this == KA2_TRANSLATION ? "Simplified Chinese" : "English";
  }

  public int group() {
    return exam.equals("考研英语") ? 0 : exam.equals("CET-6 六级") ? 1 : 2;
  }

  public boolean showCount() {
    return this == IELTS1 || this == IELTS2;
  }

  public String title() {
    return exam + " · " + subtype;
  }

  public String prompt() {
    return switch (this) {
      case KA_SMALL ->
          "Write a letter to your friend Alex, inviting them to a lecture on Chinese culture at"
              + " your university. Include the time and place, the topic, and why they would enjoy"
              + " it. Write about 100 words. Use ‘Li Ming’ instead of your own name.";
      case KA_LARGE ->
          "Write an essay of 160–200 words about the importance of persistence. Describe an"
              + " example, explain its significance, and give your comments.";
      case CET6 ->
          "Write an essay on the importance of independent thinking in university life. You should"
              + " write at least 150 words but no more than 200 words.";
      case IELTS1 ->
          "Paste your Academic Task 1 question here. For a chart or diagram, include its values and"
              + " relevant visual information before grading. Write at least 150 words.";
      case KA_TRANSLATION ->
          "将下列五个英语句子译成通顺、准确的汉语。请保留编号。原创练习，每句按 2 分练习尺度评阅。\n\n"
              + "1. The value of education lies not only in the knowledge we acquire, but also in"
              + " the questions we learn to ask.\n"
              + "2. A community becomes stronger when its members are willing to listen to views"
              + " different from their own.\n"
              + "3. Although technology has made information easier to obtain, deciding which"
              + " sources to trust still requires careful judgment.\n"
              + "4. What appears to be a small improvement today may have a lasting influence on"
              + " the way people live.\n"
              + "5. It is through repeated attempts and thoughtful reflection that individuals turn"
              + " experience into understanding.";
      case KA2_TRANSLATION ->
          "请将下列英语段落完整译成准确、通顺的汉语。原创英语二翻译练习，采用 15 分练习尺度。\n\n"
              + "Learning a new skill often begins with an uncomfortable feeling: we know what we"
              + " want to achieve, but we cannot yet do it well. This gap can be frustrating,"
              + " especially when we compare ourselves with people who have years of experience."
              + " Yet progress rarely follows a straight line. Some days bring obvious"
              + " improvements, while others seem to produce no change at all. The important thing"
              + " is to pay attention to what each attempt teaches us. A small mistake can reveal a"
              + " habit that needs to change, and a useful question can lead us to a better"
              + " approach. Instead of treating difficulty as evidence that we lack ability, we can"
              + " see it as part of the learning process. With regular practice, helpful feedback"
              + " and enough patience, activities that once demanded all our attention gradually"
              + " become more natural. Confidence then grows from experience rather than from the"
              + " expectation of immediate success.";
      case CET_TRANSLATION ->
          "请将下面的汉语段落译成英语。原创翻译练习。\n\n"
              + "近年来，越来越多的中国城市开始重视公共图书馆的建设。图书馆不仅为读者提供丰富的书籍，还组织讲座、展览和面向不同年龄群体的阅读活动。一些图书馆延长了开放时间，让工作繁忙的人也有机会在晚上享受阅读。数字技术的应用使读者可以在线查找资料和借阅电子书。不过，安静舒适的阅读空间仍然具有不可替代的价值。通过这些努力，图书馆正逐渐成为连接社区、分享知识的重要场所，也让阅读成为更多人日常生活的一部分。";
      case IELTS2 ->
          "Some people believe university students should focus on their main subject, while others"
              + " think they should study a range of subjects. Discuss both views and give your"
              + " opinion. Write at least 250 words.";
    };
  }
}
