package com.functionhx.writebench;

import android.content.Context;
import android.graphics.*;
import android.view.View;

/** Original category symbols, not official exam authority marks. */
public final class ExamIcon extends View {
  private final int kind;
  private final Paint paint = new Paint(3);

  public ExamIcon(Context c, int kind) {
    super(c);
    this.kind = kind;
    setContentDescription(kind == 0 ? "考研英语" : kind == 1 ? "CET-6 六级" : "IELTS 雅思");
  }

  @Override
  protected void onDraw(Canvas c) {
    super.onDraw(c);
    c.save();
    c.scale(getWidth() / 32f, getHeight() / 32f);
    paint.setColor(Color.rgb(50, 102, 245));
    paint.setStyle(Paint.Style.STROKE);
    paint.setStrokeWidth(1.7f);
    paint.setStrokeCap(Paint.Cap.ROUND);
    paint.setStrokeJoin(Paint.Join.ROUND);
    if (kind == 0) {
      Path p = new Path();
      p.moveTo(3, 12);
      p.lineTo(16, 6);
      p.lineTo(29, 12);
      p.lineTo(16, 18);
      p.close();
      c.drawPath(p, paint);
      p = new Path();
      p.moveTo(8, 15);
      p.lineTo(8, 22);
      p.quadTo(16, 28, 24, 22);
      p.lineTo(24, 15);
      c.drawPath(p, paint);
      c.drawLine(29, 12, 29, 23, paint);
    } else if (kind == 1) {
      c.drawRoundRect(6, 5, 25, 28, 3, 3, paint);
      c.drawLine(11, 10, 20, 10, paint);
      c.drawLine(11, 15, 20, 15, paint);
      c.drawLine(11, 20, 16, 20, paint);
    } else {
      c.drawCircle(16, 16, 12, paint);
      c.drawOval(10, 4, 22, 28, paint);
      c.drawLine(4, 16, 28, 16, paint);
      c.drawArc(5, 5, 27, 15, 0, 180, false, paint);
      c.drawArc(5, 17, 27, 27, 180, 180, false, paint);
    }
    c.restore();
  }
}
