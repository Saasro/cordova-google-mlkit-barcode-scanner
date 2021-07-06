package com.saasro.mlkit;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.AspectRatio;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LiveData;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.PorterDuff;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.ImageButton;
import android.widget.TextView;

import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.Barcode;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.common.InputImage;

import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class CaptureActivity extends AppCompatActivity implements SurfaceHolder.Callback {
  public static final String BarcodeFormat = "MLKitBarcodeFormat";
  public static final String BarcodeType = "MLKitBarcodeType";
  public static final String BarcodeValue = "MLKitBarcodeValue";

  private PreviewView mCameraView;
  private SurfaceHolder holder;
  private SurfaceView surfaceView;
  private Canvas canvas;
  private Paint paint;

  private Camera camera;
  private ListenableFuture<ProcessCameraProvider> cameraProviderFuture;
  private ExecutorService executor = Executors.newSingleThreadExecutor();
  private BarcodeScanner scanner;

  private ImageButton torchButton;
  private ImageButton mCancelButton;
  private TextView title;
  private BeepManager beepManager;



  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(getResources().getIdentifier("activity_ml_capture", "layout", getPackageName()));

    scanner = BarcodeScanning.getClient(new BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS).build());
    initCaptureActions();
    startCamera();
  }

  /***
   * Add close and torch and rest of the ui actions
   */
  private void initCaptureActions() {
    beepManager = new BeepManager(this);
    surfaceView = findViewById(getResources().getIdentifier("overlay", "id", getPackageName()));
    surfaceView.setZOrderOnTop(true);

    holder = surfaceView.getHolder();
    holder.setFormat(PixelFormat.TRANSLUCENT);
    holder.addCallback(this);
    DrawFocusRect(Color.parseColor("#FFFFFF"));

    title = ((TextView)findViewById(getResources().getIdentifier("title_tv", "id", getPackageName())));
    String titleText = getIntent().getStringExtra("title");
    if(titleText!=null){
      title.setText(titleText);
    }

    // set font
    String fontPath =  "fonts/"+ getIntent().getStringExtra("font");
    //Typeface typeface = Typeface.createFromAsset(getAssets(),  fontPath);
    //title.setTypeface(typeface);

    // set Button actions

    torchButton = ((ImageButton)findViewById(getResources().getIdentifier("torch_button", "id", getPackageName())));
    mCancelButton = ((ImageButton)findViewById(getResources().getIdentifier("cancel_btn", "id", getPackageName())));
    mCancelButton.setOnClickListener(new View.OnClickListener() {
      @Override
      public void onClick(View view) {
        setResult(Activity.RESULT_CANCELED);
        finish();
      }
    });

    torchButton.setOnClickListener(new View.OnClickListener() {
      @Override
      public void onClick(View view) {
        LiveData<Integer> flashState = camera.getCameraInfo().getTorchState();
        if (flashState.getValue() != null) {
          boolean state = flashState.getValue() == 1;
          torchButton.setBackgroundResource(getResources().getIdentifier(!state ? "flash_on" : "flash_off", "drawable", CaptureActivity.this.getPackageName()));
          camera.getCameraControl().enableTorch(!state);
        }
      }
    });


  }


  private void startCamera() {
    mCameraView = findViewById(getResources().getIdentifier("previewView", "id", getPackageName()));
    mCameraView.setPreferredImplementationMode(PreviewView.ImplementationMode.SURFACE_VIEW);

    cameraProviderFuture = ProcessCameraProvider.getInstance(this);
    cameraProviderFuture.addListener(new Runnable() {
      @Override
      public void run() {
        try {
          ProcessCameraProvider cameraProvider = cameraProviderFuture.get();
          CaptureActivity.this.bindPreview(cameraProvider);

        } catch (ExecutionException | InterruptedException e) {
          // No errors need to be handled for this Future.
          // This should never be reached.
        }
      }
    }, ContextCompat.getMainExecutor(this));
  }

  private void bindPreview(ProcessCameraProvider cameraProvider) {


    Preview preview = new Preview.Builder().build();
    CameraSelector cameraSelector = new CameraSelector.Builder()
      .requireLensFacing(CameraSelector.LENS_FACING_BACK).build();
    preview.setSurfaceProvider(mCameraView.createSurfaceProvider());

    ImageAnalysis imageAnalysis =
      new ImageAnalysis.Builder()
        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
        .setTargetAspectRatio(AspectRatio.RATIO_4_3)
        .build();
    imageAnalysis.setAnalyzer(executor, barcodeAnalyser);

    camera = cameraProvider.bindToLifecycle((LifecycleOwner) this, cameraSelector, imageAnalysis, preview);
  }

  ImageAnalysis.Analyzer barcodeAnalyser = new ImageAnalysis.Analyzer() {
    @SuppressLint("UnsafeExperimentalUsageError")
    @Override
    public void analyze(@NonNull ImageProxy image) {
      if (image == null || image.getImage() == null) {
        return;
      }

      Bitmap bmp = BitmapUtils.getBitmap(image);
      int height = bmp.getHeight();
      int width = bmp.getWidth();

      int left, right, top, bottom, boxHeight, boxWidth;

      left = (int)(width*0.1);
      right = (int)(width*0.9);

      top = (int)(height *0.30);
      bottom = (int) (height*0.70);

      boxHeight = bottom - top;
      boxWidth = right - left;

      Bitmap bitmap = Bitmap.createBitmap(bmp, left, top, boxWidth, boxHeight);

      Task<List<Barcode>> process = scanner.process(InputImage.fromBitmap(bitmap, image.getImageInfo().getRotationDegrees()));
      process.addOnSuccessListener(barcodeSuccessListener);
      process.addOnCompleteListener(new OnCompleteListener<List<Barcode>>() {
        @Override
        public void onComplete(@NonNull Task<List<Barcode>> task) {
          image.close();
        }
      });
    }
  };
  OnSuccessListener<List<Barcode>> barcodeSuccessListener = new OnSuccessListener<List<Barcode>>() {
    @Override
    public void onSuccess(List<Barcode> barcodes) {
      if (barcodes.size() > 0) {
        beepManager.playBeepSoundAndVibrate();
        for (Barcode barcode : barcodes) {
          Intent data = new Intent();
          data.putExtra(BarcodeFormat, barcode.getFormat());
          data.putExtra(BarcodeType, barcode.getValueType());
          data.putExtra(BarcodeValue, barcode.getRawValue());
          setResult(Activity.RESULT_OK, data);
          finish();
        }
      }
    }
  };


  @Override
  public void surfaceCreated(SurfaceHolder surfaceHolder) {

  }

  @Override
  public void surfaceChanged(SurfaceHolder surfaceHolder, int i, int i1, int i2) {
    DrawFocusRect(Color.parseColor("#FFFFFF"));
  }

  @Override
  public void surfaceDestroyed(SurfaceHolder surfaceHolder) {
  }

  /**
   * For drawing the rectangular box
   */
  private void DrawFocusRect(int color) {

    if (mCameraView != null) {
      int height = mCameraView.getHeight();
      int width = mCameraView.getWidth();


      int left, right, top, bottom;


      canvas = holder.lockCanvas();
      canvas.drawColor(0, PorterDuff.Mode.CLEAR);
      //border's properties
      paint = new Paint();
      paint.setStyle(Paint.Style.STROKE);
      paint.setColor(color);
      paint.setStrokeWidth(2);

      left = (int)(width*0.1);
      right = (int)(width*0.9);

      top = (int)(height *0.30);
      bottom = (int) (height*0.70);

      canvas.drawRect(new RectF(left, top, right, bottom), paint);

      holder.unlockCanvasAndPost(canvas);
    }
  }

  @Override
  protected void onDestroy() {
    super.onDestroy();
    beepManager.close();
  }
}
