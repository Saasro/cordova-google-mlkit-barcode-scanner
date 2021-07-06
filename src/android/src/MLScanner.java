  package com.saasro.mlkit;

  import android.Manifest;
  import android.content.Intent;
  import android.content.pm.PackageManager;
  import android.os.Bundle;
  import android.util.Log;
  import android.app.Activity;


  import com.google.android.gms.common.api.CommonStatusCodes;

  import org.apache.cordova.CordovaPlugin;
  import org.apache.cordova.CallbackContext;

  import org.apache.cordova.PermissionHelper;
  import org.apache.cordova.PluginResult;
  import org.json.JSONArray;
  import org.json.JSONException;
  import org.json.JSONObject;

  /**
   * This class echoes a string called from JavaScript.
   */
  public class MLScanner extends CordovaPlugin {

    private static final String LOG_TAG ="MLSCANNER";
    private static final int ML_SCANNER_CODE = 10001;
    private static final String SCAN = "scan";
    private CallbackContext callbackContext;

    private String [] permissions = { Manifest.permission.CAMERA };
    private JSONArray requestArgs;



    @Override
      public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
      this.callbackContext = callbackContext;
      this.requestArgs = args;

      if (action.equals(SCAN)) {
            if(!hasPermisssion()) {
              requestPermissions(0);
            } else {
              scan(args);
            }
          }else{
            return false;
          }
          return true;
      }

      private void scan(JSONArray args) throws JSONException {
      final CordovaPlugin that = this;
      cordova.getThreadPool().execute(new Runnable() {
        @Override
        public void run() {
          Intent intent = new Intent(that.cordova.getActivity().getBaseContext(), CaptureActivity.class);

          if (args.length() > 0) {
            JSONObject obj;
            JSONArray names;
            String key;
            Object value;

            for (int i = 0; i < args.length(); i++) {

              try {
                obj = args.getJSONObject(i);
              } catch (JSONException e) {
                Log.i(LOG_TAG, e.getLocalizedMessage());
                continue;
              }

              names = obj.names();
              for (int j = 0; j < names.length(); j++) {
                try {
                  key = names.getString(j);
                  value = obj.get(key);

                  if (value instanceof Integer) {
                    intent.putExtra(key, (Integer) value);
                  } else if (value instanceof String) {
                    intent.putExtra(key, (String) value);
                  }
                } catch (JSONException e) {
                  Log.i(LOG_TAG, e.getLocalizedMessage());
                }
              }
            }
          }

          intent.putExtra("SCAN_FORMATS", args.optInt(0, 1234));
          intent.setPackage(that.cordova.getActivity().getApplicationContext().getPackageName());
          that.cordova.startActivityForResult(that, intent, ML_SCANNER_CODE);
        }
      });
      }


    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
      super.onActivityResult(requestCode, resultCode, data);

      if (requestCode == ML_SCANNER_CODE) {
        if (resultCode == Activity.RESULT_OK) {
          if (data != null) {
            Integer barcodeFormat = data.getIntExtra(CaptureActivity.BarcodeFormat, 0);
            Integer barcodeType = data.getIntExtra(CaptureActivity.BarcodeType, 0);
            String barcodeValue = data.getStringExtra(CaptureActivity.BarcodeValue);
            try{
              JSONObject result = new JSONObject();
              result.put("text",barcodeValue);
              result.put("format",barcodeFormat);
              result.put("type",barcodeType);
              result.put("cancelled", false);
              callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, result));
              Log.d(LOG_TAG, "Barcode read: " + barcodeValue);
            } catch (JSONException e) {
              Log.d(LOG_TAG, "This should never happen");
            }

          }
        } else if (resultCode == Activity.RESULT_CANCELED) {
                JSONObject obj = new JSONObject();
                try {
                    obj.put("text", "");
                    obj.put("format", "");
                    obj.put("cancelled", true);
                } catch (JSONException e) {
                    Log.d(LOG_TAG, "This should never happen");
                }
                //this.success(new PluginResult(PluginResult.Status.OK, obj), this.callback);
                this.callbackContext.success(obj);
        }else {
          String err = data.getStringExtra("err");
          JSONArray result = new JSONArray();
          result.put(err);
          result.put("");
          result.put("");
          callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.ERROR, result));
        }
      }

    }

    /**
     * check application's permissions
     */
    public boolean hasPermisssion() {
      for(String p : permissions)
      {
        if(!PermissionHelper.hasPermission(this, p))
        {
          return false;
        }
      }
      return true;
    }

    /**
     * We override this so that we can access the permissions variable, which no longer exists in
     * the parent class, since we can't initialize it reliably in the constructor!
     *
     * @param requestCode The code to get request action
     */
    public void requestPermissions(int requestCode)
    {
      PermissionHelper.requestPermissions(this, requestCode, permissions);
    }
    /**
     * processes the result of permission request
     *
     * @param requestCode The code to get request action
     * @param permissions The collection of permissions
     * @param grantResults The result of grant
     */
    public void onRequestPermissionResult(int requestCode, String[] permissions, int[] grantResults) throws JSONException {
      PluginResult result;
      for (int r : grantResults) {
        if (r == PackageManager.PERMISSION_DENIED) {
          Log.d(LOG_TAG, "Permission Denied!");
          result = new PluginResult(PluginResult.Status.ILLEGAL_ACCESS_EXCEPTION);
          this.callbackContext.sendPluginResult(result);
          return;
        }
      }

      switch(requestCode) {
        case 0:
          scan(this.requestArgs);
          break;
      }
    }

    /**
     * This plugin launches an external Activity when the camera is opened, so we
     * need to implement the save/restore API in case the Activity gets killed
     * by the OS while it's in the background.
     */
    public void onRestoreStateForActivityResult(Bundle state, CallbackContext callbackContext) {
      this.callbackContext = callbackContext;
    }

  }
