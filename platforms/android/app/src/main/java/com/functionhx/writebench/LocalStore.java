package com.functionhx.writebench;

import android.content.Context;
import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import org.json.*;

public final class LocalStore {
  private final File directory;

  public LocalStore(Context context) {
    directory = context.getFilesDir();
  }

  public synchronized JSONObject read(String name) throws Exception {
    AtomicFile file = new AtomicFile(new File(directory, name));
    if (!file.getBaseFile().exists()) return new JSONObject();
    try (var in = file.openRead()) {
      return new JSONObject(new String(in.readAllBytes(), StandardCharsets.UTF_8));
    }
  }

  public synchronized void write(String name, JSONObject value) throws Exception {
    AtomicFile file = new AtomicFile(new File(directory, name));
    FileOutputStream out = null;
    try {
      out = file.startWrite();
      out.write(value.toString().getBytes(StandardCharsets.UTF_8));
      file.finishWrite(out);
    } catch (Exception e) {
      if (out != null) file.failWrite(out);
      throw e;
    }
  }

  public synchronized JSONArray history() throws Exception {
    return read("history.json").optJSONArray("sessions") == null
        ? new JSONArray()
        : read("history.json").getJSONArray("sessions");
  }

  public synchronized void add(JSONObject session) throws Exception {
    JSONArray previous = history(), next = new JSONArray().put(session);
    for (int i = 0; i < previous.length(); i++) next.put(previous.get(i));
    write("history.json", new JSONObject().put("sessions", next));
  }

  public synchronized void rewrite(String id, String essay) throws Exception {
    JSONArray records = history();
    for (int i = 0; i < records.length(); i++) {
      JSONObject s = records.getJSONObject(i);
      if (s.getString("id").equals(id)) {
        s.put("finalRewrite", essay);
        write("history.json", new JSONObject().put("sessions", records));
        return;
      }
    }
  }
}
