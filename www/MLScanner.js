var exec = require('cordova/exec');
const cordova = window.cordova || window.Cordova;

const defaultSettings = Object.freeze({
  types: {
    Code128: true,
    Code39: true,
    Code93: true,
    CodaBar: true,
    DataMatrix: true,
    EAN13: true,
    EAN8: true,
    ITF: true,
    QRCode: true,
    UPCA: true,
    UPCE: true,
    PDF417: true,
    Aztec: true
  },
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
    PDF417: 2048,
    AZTEC: 4096
  });
  
  const detectorType = Object.freeze({
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
  });

var scanInProgress = false;


function getBarcodeFormat(format) {
    const formatString = Object.keys(detectorFormat).find(key => detectorFormat[key] === format);
    return formatString || format;
}
  
function getBarcodeType(type) {
    const typeString = Object.keys(detectorType).find(key => detectorType[key] === type);
    return typeString || type;
}

(function (){

function MLScanner(){  }
MLScanner.prototype.scan = function (params, success, failure){
    // Default settings. Scan every barcode type.
    const settings = Object.assign({}, defaultSettings, params);

    let detectorTypes = 0;
    for (const key in settings.types) {
      if (detectorFormat.hasOwnProperty(key) && settings.types.hasOwnProperty(key) && settings.types[key] == true) {
        detectorTypes += detectorFormat[key];
      }
    }
    const title = settings.title;
    const flashOnString = settings.flashOnString
    const flashOffString = settings.flashOffString

    const args ={
        title: title,
    flashOnString: flashOnString,
    flashOffString: flashOffString,
    detectorType: detectorTypes
    };
    //this.sendScanRequest(sendSettings, success, failure);
    exec((data) => {
        console.log(data)
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
      }, 'MLScanner', 'scan', [args]);
};

var mlScanner = new MLScanner();
module.exports = mlScanner
})();
