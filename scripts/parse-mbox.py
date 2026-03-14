#!/usr/bin/env python3

import mailbox
import email
import email.utils
import email.header
import json
import argparse
import sys
import re
import html
from datetime import datetime, timezone
from pathlib import Path


NOREPLY_PATTERNS = re.compile(
    r'(noreply|no-reply|no_reply|mailer-daemon|notifications@|alerts@|donotreply|daemon@)',
    re.IGNORECASE,
)

AUTOMATED_SUBJECT_RE = re.compile(
    r'^(your order|order confirmation|shipping|delivery|password reset|'
    r'verify your|confirm your|security alert|sign-in|login|'
    r'receipt for|invoice|payment|unsubscribe)',
    re.IGNORECASE,
)

HTML_TAG_RE = re.compile(r'<[^>]+>')

BODY_MAX = 2000
PROGRESS_INTERVAL = 500


def decode_header_value(raw):
    if raw is None:
        return ""
    parts = email.header.decode_header(raw)
    decoded = []
    for data, charset in parts:
        if isinstance(data, bytes):
            decoded.append(data.decode(charset or "utf-8", errors="replace"))
        else:
            decoded.append(data)
    return " ".join(decoded)


def parse_address(raw):
    if not raw:
        return "", ""
    name, addr = email.utils.parseaddr(raw)
    return decode_header_value(name) if name else "", addr.lower()


def parse_address_list(raw):
    if not raw:
        return []
    decoded = decode_header_value(raw)
    addresses = email.utils.getaddresses([decoded])
    return [a[1].lower() for a in addresses if a[1]]


def parse_date(msg):
    raw = msg.get("Date")
    if not raw:
        return None
    try:
        parsed = email.utils.parsedate_to_datetime(raw)
        return parsed.replace(tzinfo=None) if parsed.tzinfo else parsed
    except Exception:
        return None


def strip_html(text):
    text = re.sub(r'<(style|script)[^>]*>.*?</\1>', '', text, flags=re.DOTALL | re.IGNORECASE)
    text = HTML_TAG_RE.sub('', text)
    text = html.unescape(text)
    text = re.sub(r'\n\s*\n', '\n\n', text)
    return text.strip()


def extract_body(msg):
    text_body = None
    html_body = None
    has_attachments = False

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            disposition = str(part.get("Content-Disposition", ""))
            if "attachment" in disposition:
                has_attachments = True
                continue
            if content_type == "text/plain" and text_body is None:
                try:
                    text_body = part.get_payload(decode=True)
                    charset = part.get_content_charset() or "utf-8"
                    text_body = text_body.decode(charset, errors="replace")
                except Exception:
                    text_body = None
            elif content_type == "text/html" and html_body is None:
                try:
                    html_body = part.get_payload(decode=True)
                    charset = part.get_content_charset() or "utf-8"
                    html_body = html_body.decode(charset, errors="replace")
                except Exception:
                    html_body = None
            elif content_type not in ("text/plain", "text/html", "multipart/mixed",
                                       "multipart/alternative", "multipart/related"):
                has_attachments = True
    else:
        content_type = msg.get_content_type()
        try:
            payload = msg.get_payload(decode=True)
            charset = msg.get_content_charset() or "utf-8"
            decoded = payload.decode(charset, errors="replace") if payload else ""
        except Exception:
            decoded = ""
        if content_type == "text/plain":
            text_body = decoded
        elif content_type == "text/html":
            html_body = decoded

    body = text_body if text_body else (strip_html(html_body) if html_body else "")
    return body[:BODY_MAX], has_attachments


def classify_skip(msg, from_addr, subject, body_empty):
    if NOREPLY_PATTERNS.search(from_addr):
        return "automated_sender"

    precedence = (msg.get("Precedence") or "").lower()
    if precedence in ("bulk", "list"):
        return "bulk_precedence"

    if msg.get("List-Unsubscribe"):
        return "newsletter"

    to_list = parse_address_list(msg.get("To"))
    cc_list = parse_address_list(msg.get("Cc"))
    if len(to_list) + len(cc_list) > 10:
        return "mass_recipient"

    if AUTOMATED_SUBJECT_RE.search(subject):
        return "automated_subject"

    if body_empty:
        return "empty_body"

    return None


def main():
    parser = argparse.ArgumentParser(description="Parse mbox to structured JSON for LLM processing")
    parser.add_argument("--file", required=True, help="Path to mbox file")
    parser.add_argument("--limit", type=int, default=None, help="Max emails to output after filtering")
    parser.add_argument("--since", default=None, help="Only include emails after YYYY-MM-DD")
    parser.add_argument("--batch-offset", type=int, default=0, help="Skip first N filtered emails")
    parser.add_argument("--batch-size", type=int, default=50, help="Max emails per batch")
    parser.add_argument("--stats-only", action="store_true", help="Output metadata only, no email content")
    args = parser.parse_args()

    mbox_path = Path(args.file)
    if not mbox_path.exists():
        print(f"Error: file not found: {args.file}", file=sys.stderr)
        sys.exit(1)

    since_date = None
    if args.since:
        try:
            since_date = datetime.strptime(args.since, "%Y-%m-%d")
        except ValueError:
            print(f"Error: invalid date format: {args.since} (expected YYYY-MM-DD)", file=sys.stderr)
            sys.exit(1)

    effective_limit = args.limit if args.limit is not None else float("inf")

    mbox = mailbox.mbox(str(mbox_path))

    skipped = {
        "automated_sender": 0,
        "bulk_precedence": 0,
        "newsletter": 0,
        "mass_recipient": 0,
        "automated_subject": 0,
        "empty_body": 0,
        "before_since_date": 0,
        "parse_error": 0,
    }

    filtered_emails = []
    total = 0
    filtered_count = 0
    earliest = None
    latest = None

    for msg in mbox:
        total += 1
        if total % PROGRESS_INTERVAL == 0:
            print(f"Processed {total}/unknown messages...", file=sys.stderr)

        try:
            from_name, from_addr = parse_address(msg.get("From"))
            subject = decode_header_value(msg.get("Subject"))
            body, has_attachments = extract_body(msg)
            dt = parse_date(msg)
        except Exception:
            skipped["parse_error"] += 1
            continue

        if dt:
            if earliest is None or dt < earliest:
                earliest = dt
            if latest is None or dt > latest:
                latest = dt

        skip_reason = classify_skip(msg, from_addr, subject, not body.strip())
        if skip_reason:
            skipped[skip_reason] += 1
            continue

        if since_date and dt and dt < since_date:
            skipped["before_since_date"] += 1
            continue
        if since_date and dt is None:
            skipped["before_since_date"] += 1
            continue

        filtered_count += 1
        if filtered_count > effective_limit:
            continue

        if not args.stats_only:
            batch_start = args.batch_offset
            batch_end = args.batch_offset + args.batch_size
            idx = filtered_count - 1
            if batch_start <= idx < batch_end:
                to_list = parse_address_list(msg.get("To"))
                cc_list = parse_address_list(msg.get("Cc"))
                filtered_emails.append({
                    "from_name": from_name,
                    "from_email": from_addr,
                    "to": to_list,
                    "cc": cc_list,
                    "date": dt.strftime("%Y-%m-%dT%H:%M:%S") if dt else None,
                    "subject": subject,
                    "body": body,
                    "has_attachments": has_attachments,
                })

    after_filter = min(filtered_count, int(effective_limit) if effective_limit != float("inf") else filtered_count)

    output = {
        "metadata": {
            "file": str(mbox_path.resolve()),
            "total_messages": total,
            "after_filter": after_filter,
            "skipped": {k: v for k, v in skipped.items() if v > 0},
            "batch_offset": args.batch_offset,
            "batch_size": args.batch_size,
            "emails_in_batch": len(filtered_emails),
            "date_range": {
                "earliest": earliest.strftime("%Y-%m-%d") if earliest else None,
                "latest": latest.strftime("%Y-%m-%d") if latest else None,
            },
        },
        "emails": filtered_emails,
    }

    json.dump(output, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
