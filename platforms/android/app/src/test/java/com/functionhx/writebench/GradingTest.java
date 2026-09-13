package com.functionhx.writebench;

import static org.junit.Assert.*;

import org.json.*;
import org.junit.Test;

public class GradingTest {
  private JSONObject response(double score) throws Exception {
    return new JSONObject()
        .put("score", score)
        .put("taskCompletion", 8)
        .put("language", 8)
        .put("coherence", 8)
        .put("register", 8)
        .put("summary", "准确传达原文")
        .put("improvedVersion", "学习需要耐心。")
        .put("majorErrors", new JSONArray())
        .put("minorErrors", new JSONArray())
        .put("corrections", new JSONArray());
  }

  private JSONArray reviewers(double a, double b, double c) throws Exception {
    JSONArray list = new JSONArray();
    double[] scores = {a, b, c};
    for (int i = 0; i < 3; i++)
      list.put(
          new JSONObject()
              .put("judge", "Judge " + (char) ('A' + i))
              .put("response", response(scores[i])));
    return list;
  }

  @Test
  public void translationDirectionsAndScales() {
    assertEquals(10, ExamTask.KA_TRANSLATION.maximum);
    assertEquals(15, ExamTask.KA2_TRANSLATION.maximum);
    assertEquals(15, ExamTask.CET_TRANSLATION.maximum);
    assertEquals("Simplified Chinese", ExamTask.KA2_TRANSLATION.targetLanguage());
    assertEquals("English", ExamTask.CET_TRANSLATION.targetLanguage());
    for (ExamTask t : ExamTask.values())
      if (t.isTranslation()) {
        assertFalse(t.showCount());
        assertFalse(t.prompt().isBlank());
      }
    assertEquals(0, ExamTask.KA2_TRANSLATION.group());
    assertEquals(1, ExamTask.CET_TRANSLATION.group());
  }

  @Test
  public void aggregatesChineseAnswerLocally() throws Exception {
    JSONObject r =
        GradingEngine.aggregate(reviewers(12, 13, 13), ExamTask.KA2_TRANSLATION, "学习需要耐心。");
    assertEquals(13, r.getDouble("finalScore"), 0);
    assertEquals("High", r.getString("confidence"));
    assertEquals(
        "Low",
        GradingEngine.aggregate(reviewers(8, 12, 13), ExamTask.KA2_TRANSLATION, "学习需要耐心。")
            .getString("confidence"));
  }

  @Test
  public void rejectsIncompleteAndDuplicateJudges() throws Exception {
    assertThrows(
        Exception.class,
        () -> GradingEngine.aggregate(new JSONArray(), ExamTask.KA2_TRANSLATION, "译文"));
    JSONArray list = reviewers(8, 8, 8);
    list.getJSONObject(2).put("judge", "Judge A");
    assertThrows(
        Exception.class, () -> GradingEngine.aggregate(list, ExamTask.KA_TRANSLATION, "译文"));
  }

  @Test
  public void validatesTranslationCorrectionsAndOriginalEvidence() throws Exception {
    JSONObject r = response(12);
    JSONObject c =
        new JSONObject()
            .put("original", "学习")
            .put("corrected", "练习")
            .put("category", "Mistranslation")
            .put("severity", "major")
            .put("explanation", "原文指 practice");
    r.getJSONArray("corrections").put(c);
    GradingEngine.validate(r, 15, "学习需要耐心。");
    assertThrows(Exception.class, () -> GradingEngine.validate(r, 10, "学习需要耐心。"));
    c.put("original", "凭空引用");
    assertThrows(Exception.class, () -> GradingEngine.validate(r, 15, "学习需要耐心。"));
  }

  @Test
  public void missingKeyCannotReturnDemoResult() {
    assertThrows(
        Exception.class,
        () -> new GradingEngine().grade(ExamTask.KA2_TRANSLATION, "source", "译文", "rubric", ""));
  }
}
