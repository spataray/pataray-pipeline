/**
 * PATARAY PIPELINE — Google Apps Script
 *
 * Receives form submissions from the landing page and writes them to this Google Sheet.
 *
 * SETUP:
 *   1. Create a new Google Sheet (name it "Pataray Submissions")
 *   2. In Row 1, add headers: timestamp | email | niche | channel_status | request_type | status
 *   3. Go to Extensions > Apps Script
 *   4. Delete the default code, paste this entire file
 *   5. Click Deploy > New Deployment
 *   6. Type: Web app
 *   7. Execute as: Me
 *   8. Who has access: Anyone
 *   9. Click Deploy — copy the Web App URL
 *  10. Paste that URL into landing-page.html (replace APPS_SCRIPT_URL)
 *
 *  ALSO — Publish the sheet for the poller:
 *   1. File > Share > Publish to web
 *   2. Choose "Sheet1" and "Comma-separated values (.csv)"
 *   3. Click Publish — copy that CSV URL
 *   4. Paste into poc/poll-sheets.py (replace SHEET_CSV_URL)
 */

function doPost(e) {
  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    var data = JSON.parse(e.postData.contents);

    var timestamp = new Date().toISOString();
    var email = data.email || '';
    var niche = data.niche || '';
    var channelStatus = data.channel_status || '';
    var requestType = data.request_type || 'full_channel_build';
    var status = 'pending';

    sheet.appendRow([timestamp, email, niche, channelStatus, requestType, status]);

    return ContentService
      .createTextOutput(JSON.stringify({ ok: true, message: 'Submission received' }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function doGet(e) {
  return ContentService
    .createTextOutput(JSON.stringify({ status: 'Pataray Pipeline receiver is running' }))
    .setMimeType(ContentService.MimeType.JSON);
}
