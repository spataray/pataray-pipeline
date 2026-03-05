#!/usr/bin/env python3
"""
Sends pipeline results to a customer via a professional HTML email.

Usage:
    python3 poc/send-email.py \
        --to customer@example.com \
        --niche "Horror / Supernatural" \
        --output-dir submissions/processing/20260301-120000_horror_output

Uses env vars GMAIL_USER and GMAIL_APP_PASSWORD (set in crontab or bashrc).
"""

import argparse
import email.mime.application
import email.mime.multipart
import email.mime.text
import os
import smtplib
import sys


# File descriptions for the email body
FILE_INFO = {
    "00-getting-started.html": {
        "icon": "&#x1F680;",
        "label": "Getting Started Guide",
        "desc": "Step-by-step instructions for turning your scripts into videos",
    },
    "01-niche-research.html": {
        "icon": "&#x1F50D;",
        "label": "Niche Research Report",
        "desc": "Market data, CPM ranges, competition analysis, and video ideas",
    },
    "02-channel-blueprint.html": {
        "icon": "&#x1F4CB;",
        "label": "Channel Blueprint",
        "desc": "Channel name, brand voice, audience persona, and 30-day content calendar",
    },
    "03-script-v01.txt": {
        "icon": "&#x1F4DD;",
        "label": "Video Script #1",
        "desc": "Ready to paste into Pictory AI, InVideo, or CapCut",
    },
    "03-script-v02.txt": {
        "icon": "&#x1F4DD;",
        "label": "Video Script #2",
        "desc": "Ready to paste into Pictory AI, InVideo, or CapCut",
    },
    "03-script-v03.txt": {
        "icon": "&#x1F4DD;",
        "label": "Video Script #3",
        "desc": "Ready to paste into Pictory AI, InVideo, or CapCut",
    },
    "04-thumbnail-guide.html": {
        "icon": "&#x1F3A8;",
        "label": "Thumbnail Design Guide",
        "desc": "AI image prompts and Canva walkthrough for each video",
    },
    "05-pinned-comments.html": {
        "icon": "&#x1F4AC;",
        "label": "Pinned Comments",
        "desc": "Copy-paste engagement comments for each video",
    },
}


def build_html_email(to_addr, from_addr, niche, output_dir, reorder_code="", request_type="full_channel_build"):
    """Build professional HTML email with dark theme."""
    msg = email.mime.multipart.MIMEMultipart("mixed")
    msg["From"] = from_addr
    msg["To"] = to_addr

    if request_type == "reorder_scripts":
        msg["Subject"] = f"Your New Scripts Are Ready — {niche}"
    else:
        msg["Subject"] = f"Your AI Channel Package Is Ready — {niche}"

    files = sorted(
        f for f in os.listdir(output_dir)
        if os.path.isfile(os.path.join(output_dir, f)) and not f.startswith(".")
    )

    # Build file cards HTML
    file_cards = ""
    for f in files:
        info = FILE_INFO.get(f, {"icon": "&#x1F4CE;", "label": f, "desc": ""})
        ext_badge = "HTML" if f.endswith(".html") else "TXT"
        badge_color = "#6366f1" if f.endswith(".html") else "#10b981"
        file_cards += f"""
        <tr>
          <td style="padding:12px 16px;border-bottom:1px solid #2a2b3d;font-size:24px;width:40px;text-align:center;">{info['icon']}</td>
          <td style="padding:12px 16px;border-bottom:1px solid #2a2b3d;">
            <div style="color:#ffffff;font-weight:700;font-size:14px;">{info['label']}
              <span style="display:inline-block;background:{badge_color};color:#fff;font-size:10px;padding:2px 6px;border-radius:4px;margin-left:6px;font-weight:600;">{ext_badge}</span>
            </div>
            <div style="color:#888;font-size:12px;margin-top:2px;">{info['desc']}</div>
          </td>
        </tr>"""

    html = f"""<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background-color:#0a0b10;font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0a0b10;">
<tr><td align="center" style="padding:40px 20px;">
<table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

  <!-- Header -->
  <tr><td style="padding:32px 32px 24px;background:linear-gradient(135deg,#1a1b26,#13141f);border-radius:16px 16px 0 0;border:1px solid #2a2b3d;border-bottom:none;">
    <div style="display:inline-block;background:linear-gradient(135deg,#6366f1,#22d3ee);border-radius:10px;padding:8px 14px;margin-bottom:16px;">
      <span style="color:#fff;font-weight:800;font-size:14px;">AI</span>
    </div>
    <h1 style="color:#ffffff;font-size:24px;font-weight:800;margin:0 0 8px;">Your Channel Package Is Ready</h1>
    <p style="color:#888;font-size:14px;margin:0;">Niche: <span style="color:#67e8f9;font-weight:600;">{niche}</span></p>
  </td></tr>

  <!-- Pipeline badge -->
  <tr><td style="padding:0 32px 24px;background:#1a1b26;border-left:1px solid #2a2b3d;border-right:1px solid #2a2b3d;">
    <table cellpadding="0" cellspacing="0" width="100%" style="background:#13141f;border-radius:10px;border:1px solid #2a2b3d;">
      <tr>
        <td style="padding:12px 16px;text-align:center;">
          <span style="color:#10b981;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;">&#x2713; Niche Research</span>
        </td>
        <td style="padding:12px 4px;text-align:center;color:#333;">&#x25B8;</td>
        <td style="padding:12px 16px;text-align:center;">
          <span style="color:#10b981;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;">&#x2713; Blueprint</span>
        </td>
        <td style="padding:12px 4px;text-align:center;color:#333;">&#x25B8;</td>
        <td style="padding:12px 16px;text-align:center;">
          <span style="color:#10b981;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;">&#x2713; Scripts</span>
        </td>
        <td style="padding:12px 4px;text-align:center;color:#333;">&#x25B8;</td>
        <td style="padding:12px 16px;text-align:center;">
          <span style="color:#10b981;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;">&#x2713; Delivered</span>
        </td>
      </tr>
    </table>
  </td></tr>

  <!-- What's attached -->
  <tr><td style="padding:0 32px 24px;background:#1a1b26;border-left:1px solid #2a2b3d;border-right:1px solid #2a2b3d;">
    <h2 style="color:#fff;font-size:16px;margin:0 0 16px;font-weight:700;">What's In Your Package</h2>
    <table width="100%" cellpadding="0" cellspacing="0" style="background:#13141f;border-radius:10px;border:1px solid #2a2b3d;">
      {file_cards}
    </table>
  </td></tr>

  <!-- Quick start steps -->
  <tr><td style="padding:0 32px 24px;background:#1a1b26;border-left:1px solid #2a2b3d;border-right:1px solid #2a2b3d;">
    <h2 style="color:#fff;font-size:16px;margin:0 0 16px;font-weight:700;">Quick Start — Your First Video in 30 Minutes</h2>
    <table cellpadding="0" cellspacing="0" width="100%">
      <tr>
        <td style="padding:8px 0;vertical-align:top;">
          <span style="display:inline-block;width:28px;height:28px;background:#4338ca;color:#fff;border-radius:50%;text-align:center;line-height:28px;font-size:13px;font-weight:700;">1</span>
        </td>
        <td style="padding:8px 0 8px 12px;color:#b0b0c0;font-size:13px;">
          <strong style="color:#fff;">Open the Getting Started Guide</strong> — it walks you through everything
        </td>
      </tr>
      <tr>
        <td style="padding:8px 0;vertical-align:top;">
          <span style="display:inline-block;width:28px;height:28px;background:#0e7490;color:#fff;border-radius:50%;text-align:center;line-height:28px;font-size:13px;font-weight:700;">2</span>
        </td>
        <td style="padding:8px 0 8px 12px;color:#b0b0c0;font-size:13px;">
          <strong style="color:#fff;">Pick a script</strong> — open any .txt file and copy the entire text
        </td>
      </tr>
      <tr>
        <td style="padding:8px 0;vertical-align:top;">
          <span style="display:inline-block;width:28px;height:28px;background:#065f46;color:#fff;border-radius:50%;text-align:center;line-height:28px;font-size:13px;font-weight:700;">3</span>
        </td>
        <td style="padding:8px 0 8px 12px;color:#b0b0c0;font-size:13px;">
          <strong style="color:#fff;">Paste into Pictory AI or InVideo</strong> — the tool turns your script into a video with voice, footage, and music in ~15 minutes
        </td>
      </tr>
      <tr>
        <td style="padding:8px 0;vertical-align:top;">
          <span style="display:inline-block;width:28px;height:28px;background:#92400e;color:#fff;border-radius:50%;text-align:center;line-height:28px;font-size:13px;font-weight:700;">4</span>
        </td>
        <td style="padding:8px 0 8px 12px;color:#b0b0c0;font-size:13px;">
          <strong style="color:#fff;">Create your thumbnail</strong> — use the AI prompts in the thumbnail guide with Canva (free)
        </td>
      </tr>
      <tr>
        <td style="padding:8px 0;vertical-align:top;">
          <span style="display:inline-block;width:28px;height:28px;background:#166534;color:#fff;border-radius:50%;text-align:center;line-height:28px;font-size:13px;font-weight:700;">5</span>
        </td>
        <td style="padding:8px 0 8px 12px;color:#b0b0c0;font-size:13px;">
          <strong style="color:#fff;">Upload to YouTube &amp; pin your comment</strong> — copy-paste from the pinned comments file
        </td>
      </tr>
    </table>
  </td></tr>

  {"" if not reorder_code else '''<!-- Reorder Code -->
  <tr><td style="padding:0 32px 24px;background:#1a1b26;border-left:1px solid #2a2b3d;border-right:1px solid #2a2b3d;">
    <div style="background:linear-gradient(135deg,#1e1b4b,#172554);border:1px solid #4338ca;border-radius:12px;padding:24px;text-align:center;">
      <p style="color:#a5b4fc;font-size:13px;margin:0 0 12px;font-weight:600;">Your Reorder Code</p>
      <div style="font-family:'Courier New',monospace;font-size:32px;font-weight:800;color:#fff;letter-spacing:8px;margin:0 0 12px;">''' + reorder_code + '''</div>
      <p style="color:#888;font-size:12px;margin:0;">Want more scripts? Go to the order form, click <strong style="color:#67e8f9;">"I Have a Reorder Code"</strong>, and enter this code. We'll generate new scripts that match your channel's voice and style.</p>
    </div>
  </td></tr>'''}

  <!-- Footer -->
  <tr><td style="padding:24px 32px;background:#13141f;border-radius:0 0 16px 16px;border:1px solid #2a2b3d;border-top:none;text-align:center;">
    <p style="color:#666;font-size:12px;margin:0 0 4px;">Questions? Just reply to this email.</p>
    <p style="color:#555;font-size:11px;margin:0;">Faceless AI Channel Builder &mdash; Built by a creator, for creators.</p>
  </td></tr>

</table>
</td></tr>
</table>
</body>
</html>"""

    # Attach HTML body as alternative
    html_part = email.mime.multipart.MIMEMultipart("alternative")
    # Plain text fallback
    plain = f"Your AI channel package for the \"{niche}\" niche is ready!\n\n"
    plain += "See the attached files for your complete channel package.\n\n"
    plain += "— Faceless AI Channel Builder"
    html_part.attach(email.mime.text.MIMEText(plain, "plain"))
    html_part.attach(email.mime.text.MIMEText(html, "html"))
    msg.attach(html_part)

    # Attach files
    for filename in files:
        filepath = os.path.join(output_dir, filename)
        with open(filepath, "rb") as f:
            if filename.endswith(".html"):
                att = email.mime.text.MIMEText(f.read().decode("utf-8"), "html")
                att.add_header("Content-Disposition", "attachment", filename=filename)
            else:
                att = email.mime.application.MIMEApplication(f.read())
                att.add_header("Content-Disposition", "attachment", filename=filename)
            msg.attach(att)

    return msg


def send(msg, user, password):
    """Send email via Gmail SMTP."""
    with smtplib.SMTP("smtp.gmail.com", 587) as server:
        server.starttls()
        server.login(user, password)
        server.send_message(msg)


def main():
    parser = argparse.ArgumentParser(description="Send pipeline results via email")
    parser.add_argument("--to", required=True, help="Recipient email")
    parser.add_argument("--niche", required=True, help="Niche name for subject line")
    parser.add_argument("--output-dir", required=True, help="Directory with output files")
    parser.add_argument("--reorder-code", default="", help="Reorder code for returning customers")
    parser.add_argument("--request-type", default="full_channel_build", help="Request type (full_channel_build or reorder_scripts)")
    args = parser.parse_args()

    gmail_user = os.environ.get("GMAIL_USER", "spataray@gmail.com")
    gmail_pass = os.environ.get("GMAIL_APP_PASSWORD")

    if not gmail_pass:
        print("ERROR: GMAIL_APP_PASSWORD env variable not set.")
        sys.exit(1)

    if not os.path.isdir(args.output_dir):
        print(f"ERROR: Output directory not found: {args.output_dir}")
        sys.exit(1)

    # Last line of defense: refuse to send email with 0 attachments
    deliverables = [
        f for f in os.listdir(args.output_dir)
        if (os.path.isfile(os.path.join(args.output_dir, f))
            and os.path.getsize(os.path.join(args.output_dir, f)) > 0
            and not f.startswith("."))
    ]
    if not deliverables:
        print(f"ERROR: Output directory is empty, refusing to send email with 0 attachments: {args.output_dir}")
        sys.exit(1)

    print(f"Building email to {args.to} ({len(deliverables)} file(s))...")
    msg = build_html_email(args.to, gmail_user, args.niche, args.output_dir, args.reorder_code, args.request_type)

    print(f"Sending via smtp.gmail.com as {gmail_user}...")
    send(msg, gmail_user, gmail_pass)
    print("Email sent successfully.")


if __name__ == "__main__":
    main()
