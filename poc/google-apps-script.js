/**
 * FACELESS AI CHANNEL BUILDER — Google Apps Script
 *
 * Receives form submissions from the landing page, tracks pipeline status,
 * and serves status updates to the frontend.
 *
 * SETUP:
 *   1. Create a new Google Sheet (name it "Faceless AI Submissions")
 *   2. In Row 1, add headers: timestamp | email | niche | channel_status | request_type | status | order_id | pipeline_step | pipeline_message | reorder_code | channel_name
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
  var channelName = data.channel_name || '';

  sheet.appendRow([timestamp, email, niche, channelStatus, requestType, status, orderId, pipelineStep, pipelineMessage, reorderCode, channelName]);

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

// ─────────────────────────────────────────────────────────────
// CHANNEL NAME SUGGESTER
// ─────────────────────────────────────────────────────────────
// Requires: ANTHROPIC_API_KEY in Project Settings > Script Properties
// Optional: YOUTUBE_API_KEY in Script Properties (for availability checks)
// Setup:    Create a "NameSuggestions" sheet tab — it's auto-created on first use.
// Sheet columns: A=niche_key | B=suggestions_json | C=created_at

function handleGetSuggestions(e) {
  var niche = (e && e.parameter && e.parameter.niche) || '';
  var fresh = (e && e.parameter && e.parameter.fresh) === '1';

  if (!niche) {
    return jsonOk({ ok: false, error: 'Missing niche' });
  }

  var nicheKey = niche.trim().toLowerCase();

  // Return cached batch unless fresh requested
  if (!fresh) {
    var cached = getCachedSuggestions(nicheKey);
    if (cached) {
      return jsonOk({ ok: true, suggestions: cached, from_cache: true });
    }
  }

  // Generate via Claude
  var suggestions = generateSuggestions(niche);
  if (!suggestions) {
    return jsonOk({ ok: false, error: 'Failed to generate suggestions' });
  }

  cacheSuggestions(nicheKey, suggestions);
  return jsonOk({ ok: true, suggestions: suggestions, from_cache: false });
}

function handleCheckName(e) {
  var name = (e && e.parameter && e.parameter.name) || '';
  if (!name) {
    return jsonOk({ ok: false, error: 'Missing name' });
  }

  var apiKey = PropertiesService.getScriptProperties().getProperty('YOUTUBE_API_KEY');
  if (!apiKey) {
    return jsonOk({ ok: true, status: 'manual_check', message: 'Search YouTube to verify the name is available.' });
  }

  try {
    var url = 'https://www.googleapis.com/youtube/v3/search?part=snippet&q='
      + encodeURIComponent(name) + '&type=channel&maxResults=5&key=' + apiKey;
    var resp = UrlFetchApp.fetch(url, { muteHttpExceptions: true });
    var data = JSON.parse(resp.getContentText());
    var items = data.items || [];
    var lowerName = name.toLowerCase().trim();

    var exactMatch = items.some(function(item) {
      return (item.snippet.channelTitle || '').toLowerCase().trim() === lowerName;
    });
    var similarCount = items.filter(function(item) {
      var title = (item.snippet.channelTitle || '').toLowerCase();
      return title.includes(lowerName) || lowerName.includes(title);
    }).length;

    if (exactMatch) {
      return jsonOk({ ok: true, status: 'taken', message: 'A channel with this exact name already exists.' });
    } else if (similarCount > 0) {
      return jsonOk({ ok: true, status: 'similar', message: similarCount + ' similar channel(s) found — you can still use this name.' });
    } else {
      return jsonOk({ ok: true, status: 'available', message: 'Looks clear — no similar channels found!' });
    }
  } catch (err) {
    return jsonOk({ ok: true, status: 'manual_check', message: 'Search YouTube to verify availability.' });
  }
}

function generateSuggestions(niche) {
  var apiKey = PropertiesService.getScriptProperties().getProperty('ANTHROPIC_API_KEY');
  if (!apiKey) return null;

  var prompt = 'You are a YouTube channel naming expert. A creator wants to launch a faceless YouTube channel in the "'
    + niche + '" niche.\n\n'
    + 'Generate 5 ORIGINAL channel name ideas. Requirements:\n'
    + '- Creative, memorable, and easy to say/spell\n'
    + '- Not a copy of any well-known existing channel\n'
    + '- Suitable for a faceless/anonymous creator\n'
    + '- Each should hint at the niche without being generic\n\n'
    + 'Return ONLY a valid JSON array — no markdown, no explanation:\n'
    + '[{"name": "Channel Name", "tagline": "One sentence describing the unique angle"}, ...]';

  var payload = {
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 600,
    messages: [{ role: 'user', content: prompt }]
  };

  var options = {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01'
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };

  try {
    var resp = UrlFetchApp.fetch('https://api.anthropic.com/v1/messages', options);
    var result = JSON.parse(resp.getContentText());
    var text = (result.content[0].text || '').trim();
    // Strip markdown code fences if model wraps in them
    text = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '');
    return JSON.parse(text);
  } catch (err) {
    return null;
  }
}

function getCachedSuggestions(nicheKey) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('NameSuggestions');
  if (!sheet) return null;

  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return null;

  var data = sheet.getRange(2, 1, lastRow - 1, 2).getValues();
  for (var i = 0; i < data.length; i++) {
    if (data[i][0] === nicheKey) {
      try { return JSON.parse(data[i][1]); } catch (e) { return null; }
    }
  }
  return null;
}

function cacheSuggestions(nicheKey, suggestions) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('NameSuggestions');
  if (!sheet) {
    sheet = ss.insertSheet('NameSuggestions');
    sheet.appendRow(['niche_key', 'suggestions_json', 'created_at']);
  }

  var lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    var data = sheet.getRange(2, 1, lastRow - 1, 2).getValues();
    for (var i = 0; i < data.length; i++) {
      if (data[i][0] === nicheKey) {
        // Append new suggestions to existing cache for this niche
        var existing = [];
        try { existing = JSON.parse(data[i][1]); } catch (e) {}
        var combined = existing.concat(suggestions);
        sheet.getRange(i + 2, 2).setValue(JSON.stringify(combined));
        sheet.getRange(i + 2, 3).setValue(new Date().toISOString());
        return;
      }
    }
  }

  sheet.appendRow([nicheKey, JSON.stringify(suggestions), new Date().toISOString()]);
}

function jsonOk(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet(e) {
  var action = (e && e.parameter && e.parameter.action) || '';

  if (action === 'status') {
    return handleGetStatus(e);
  }

  if (action === 'get_suggestions') {
    return handleGetSuggestions(e);
  }

  if (action === 'check_name') {
    return handleCheckName(e);
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
