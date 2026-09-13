package com.functionhx.writebench;

import static androidx.test.platform.app.InstrumentationRegistry.getInstrumentation;
import static org.junit.Assert.*;

import android.content.Context;
import android.content.ContextWrapper;
import android.graphics.BitmapFactory;
import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions;
import java.io.File;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import org.json.JSONObject;
import org.junit.Test;

public class DeviceServicesTest {
  @Test
  public void testRealOnDeviceOCR() throws Exception {
    try (var input = getInstrumentation().getContext().getAssets().open("ocr-fixture.png")) {
      var bitmap = BitmapFactory.decodeStream(input);
      var recognizer =
          TextRecognition.getClient(new ChineseTextRecognizerOptions.Builder().build());
      try {
        var result =
            Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)), 60, TimeUnit.SECONDS);
        assertTrue(result.getText().contains("Alex"));
      } finally {
        recognizer.close();
        bitmap.recycle();
      }
    }
  }

  @Test
  public void testAtomicHistoryAndChineseRewrite() throws Exception {
    Context actual = getInstrumentation().getTargetContext();
    File folder = new File(actual.getCacheDir(), "service-test-" + UUID.randomUUID());
    assertTrue(folder.mkdirs());
    Context isolated =
        new ContextWrapper(actual) {
          @Override
          public File getFilesDir() {
            return folder;
          }
        };
    LocalStore store = new LocalStore(isolated);
    store.add(new JSONObject().put("id", "test-session").put("essay", "原始译文"));
    store.rewrite("test-session", "忠实完整的改译");
    LocalStore restored = new LocalStore(isolated);
    assertEquals("原始译文", restored.history().getJSONObject(0).getString("essay"));
    assertEquals("忠实完整的改译", restored.history().getJSONObject(0).getString("finalRewrite"));
  }
}
