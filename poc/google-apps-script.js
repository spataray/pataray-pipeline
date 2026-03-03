/**
 * FACELESS AI CHANNEL BUILDER — Google Apps Script
 *
 * Receives form submissions from the landing page, tracks pipeline status,
 * and serves status updates to the frontend.
 *
 * SETUP:
 *   1. Create a new Google Sheet (name it "Faceless AI Submissions")
 *   2. In Row 1, add headers: timestamp | email | niche | channel_status | request_type | status | order_id | pipeline_step | pipeline_message | reorder_code
 *   3. Go to Extensions > Apps Script
 *   4. Delete the default code, paste this entire file
 *   5. Click Deploy > New Deployment
 *   6. Type: Web app
 *   7. Execute as: Me
 *   8. Who has access: Anyone
 *   9. Click Deploy — copy the Web App URL
 *  10. Paste that URL into index.html (replace APPS_SCRIPT_URL)
 *
 *  ALSO — Publish the sheet for the poller:
 *   1. File > Share > Publish to web
 *   2. Choose "Sheet1" and "Comma-separated values (.csv)"
 *   3. Click Publish — copy that CSV URL
 *   4. Paste into poc/poll-sheets.py (replace SHEET_CSV_URL)
 *
 *  REDEPLOYING after changes:
 *   Deploy > Manage Deployments > Edit (pencil) > Version: New version > Deploy
 */

function doPost(e) {
  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    var data = JSON.parse(e.postData.contents);

    var action = data.action || 'submit';

    if (action === 'update_status') {
      return handleUpdateStatus(sheet, data);
    }

    // Default: submit new order
    return handleSubmit(sheet, data);

  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function handleSubmit(sheet, data) {
  var timestamp = new Date().toISOString();
  var email = data.email || '';
  var niche = data.niche || '';
  var channelStatus = data.channel_status || '';
  var requestType = data.request_type || 'full_channel_build';
  var status = 'pending';
  var orderId = data.order_id || '';
  var pipelineStep = 0;
  var pipelineMessage = '';

  var reorderCode = data.reorder_code || '';

  sheet.appendRow([timestamp, email, niche, channelStatus, requestType, status, orderId, pipelineStep, pipelineMessage, reorderCode]);

  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, message: 'Submission received', order_id: orderId }))
    .setMimeType(ContentService.MimeType.JSON);
}

function handleUpdateStatus(sheet, data) {
  var orderId = data.order_id || '';
  if (!orderId) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: 'Missing order_id' }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  var row = findRowByOrderId(sheet, orderId);
  if (!row) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: 'Order not found: ' + orderId }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  // Update columns: F=status (6), H=pipeline_step (8), I=pipeline_message (9)
  if (data.status) {
    sheet.getRange(row, 6).setValue(data.status);
  }
  if (data.pipeline_step !== undefined) {
    sheet.getRange(row, 8).setValue(data.pipeline_step);
  }
  if (data.pipeline_message !== undefined) {
    sheet.getRange(row, 9).setValue(data.pipeline_message);
  }

  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, message: 'Status updated' }))
    .setMimeType(ContentService.MimeType.JSON);
}

function findRowByOrderId(sheet, orderId) {
  // order_id is in column G (7th column)
  var data = sheet.getRange(1, 7, sheet.getLastRow(), 1).getValues();
  for (var i = data.length - 1; i >= 0; i--) {
    if (data[i][0] === orderId) {
      return i + 1; // 1-indexed row number
    }
  }
  return null;
}

function doGet(e) {
  var action = (e && e.parameter && e.parameter.action) || '';

  if (action === 'status') {
    return handleGetStatus(e);
  }

  return ContentService
    .createTextOutput(JSON.stringify({ status: 'Faceless AI Pipeline receiver is running' }))
    .setMimeType(ContentService.MimeType.JSON);
}

function handleGetStatus(e) {
  var orderId = e.parameter.order_id || '';
  if (!orderId) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: 'Missing order_id' }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var row = findRowByOrderId(sheet, orderId);

  if (!row) {
    // Order may not have propagated yet — return queued
    return ContentService
      .createTextOutput(JSON.stringify({
        ok: true,
        status: 'queued',
        pipeline_step: 0,
        pipeline_message: 'Your order is in the queue...'
      }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  // Read: F=status (6), H=pipeline_step (8), I=pipeline_message (9), J=reorder_code (10)
  var rowData = sheet.getRange(row, 1, 1, 10).getValues()[0];
  var status = rowData[5] || 'pending';
  var pipelineStep = rowData[7] || 0;
  var pipelineMessage = rowData[8] || '';
  var reorderCode = rowData[9] || '';

  return ContentService
    .createTextOutput(JSON.stringify({
      ok: true,
      status: status,
      pipeline_step: Number(pipelineStep),
      pipeline_message: String(pipelineMessage),
      reorder_code: String(reorderCode)
    }))
    .setMimeType(ContentService.MimeType.JSON);
}
