const cordova = window.cordova || window.Cordova;

const defaultSettings = Object.freeze({
  types: {
    CODE_128: true,
    CODE_39: true,
    CODE_93: true,
    CODA_BAR: true,
    DATA_MATRIX: true,
    EAN_13: true,
    EAN_8: true,
    ITF: true,
    QR_CODE: true,
    UPCA: true,
    UPCE: true,
    PDF417: true,
    Aztec: true
  },
  detectorSize: 0.6
});
const detectorFormat = Object.freeze({
  CODE_128: 1,
  CODE_39: 2,
  CODE_93: 4,
  CODABAR: 8,
  DATA_MATRIX: 16,
  EAN_13: 32,
  EAN_8: 64,
  ITF: 128,
  QR_CODE: 256,
  UPCA: 512,
  UPCE: 1024,
  PDF_417: 2048,
  AZTEC: 4096
});

const detectorType = {
  CONTACT_INFO: 1,
  EMAIL: 2,
  ISBN: 3,
  PHONE: 4,
  PRODUCT: 5,
  SMS: 6,
  TEXT: 7,
  URL: 8,
  WIFI: 9,
  GEO: 10,
  CALENDAR_EVENT: 11,
  DRIVER_LICENSE: 12
};

function getBarcodeFormat(format) {
  // for somereasons object.find is returning undefined
   // const formatString = Object.keys(detectorFormat).find(key => detectorFormat[key] === format)
  let formatString= "";
  for (const [key, value] of Object.entries(detectorFormat)) {
    if(value == format){
      formatString = key;
      break;
    }
  }
  return formatString;
}

function getBarcodeType(type) {
  const typeString = Object.keys(detectorType).find(key => detectorType[key] === type);
  return typeString || type;
}

(function () {
  function MLKitBarcodeScanner() { }

  MLKitBarcodeScanner.prototype.scan = function (params, success, failure) {
    // Default settings. Scan every barcode type.
    const settings = Object.assign({}, defaultSettings, params);

    // GMVDetectorConstants values allow us to pass an integer sum of all the desired barcode types to the scanner.
    let detectorTypes = 0;
    for (const key in settings.types) {
      if (detectorFormat.hasOwnProperty(key) && settings.types.hasOwnProperty(key) && settings.types[key] == true) {
        detectorTypes += detectorFormat[key];
      }
    }

    const multiplier = settings.detectorSize;
/*  const isPortrait = window.innerWidth < window.innerHeight;
    const detectorWidth = multiplier;
    const detectorHeight = isPortrait
      ? window.innerWidth * multiplier / window.innerHeight
      : window.innerHeight * multiplier / window.innerWidth */

    // Order of this settings object is critical. It will be passed in a basic array format and must be in the order shown.
    const args = {
      //Position 1
      detectorType: detectorTypes,
      //Position 2
      detectorSize: multiplier,
      title: settings.title,
      flashOnString : settings.flashOnString,
      flashOffString: settings.flashOffString
    };
    const sendSettings = [];
    for (const key in args) {
      if (args.hasOwnProperty(key)) {
        sendSettings.push(args[key]);
      }
    }
    this.sendScanRequest(sendSettings, success, failure);
  };

  MLKitBarcodeScanner.prototype.sendScanRequest = function (settings, success, failure) {
    cordova.exec((data) => {
      success({
        cancelled: data.cancelled,
        text: data.text,
        format: getBarcodeFormat(data.format),
        type: getBarcodeType(data.type)
      });
    }, (err) => {
      switch (err[0]) {
        case null:
        case 'USER_CANCELLED':
          failure({ cancelled: true, message: 'The scan was cancelled.' });
          break;
        case 'SCANNER_OPEN':
          failure({ cancelled: false, message: 'Scanner already open.' });
          break;
        default:
          failure({ cancelled: false, message: err });
          break;
      }
    }, 'MLScanner', 'startScan', settings);
  };

  module.exports = new MLKitBarcodeScanner();
})();