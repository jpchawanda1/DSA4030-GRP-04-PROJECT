#!/usr/bin/env python3
"""
Generates a synthetic "company documents" dataset for the Group 4 Secure Cloud
Storage project: HR records, finance invoices, and contracts — three document
categories mapped 1:1 to the three MinIO buckets created by
minio/init/init-minio.sh (hr-documents, finance-documents, contracts-documents).

Records are written as sharded JSON Lines files under dataset/output/<bucket>/
so upload_dataset.py can push each shard as one object (mirrors how a real
company would batch-export documents rather than writing 100k+ individual
objects).

Usage:
    python3 generate_dataset.py --records-per-category 40000 --shard-size 2000
"""
import argparse
import json
import os
import random
from datetime import datetime, timedelta

from faker import Faker

DEPARTMENTS = ["Engineering", "Sales", "Marketing", "Human Resources", "Finance",
               "Legal", "Operations", "Customer Support", "IT", "Procurement"]
JOB_TITLES = ["Analyst", "Manager", "Senior Manager", "Director", "Associate",
              "Specialist", "Coordinator", "Engineer", "Consultant", "VP"]
CONTRACT_TYPES = ["Service Agreement", "NDA", "Vendor Contract", "Lease Agreement",
                   "Employment Contract", "Partnership Agreement", "Licensing Agreement"]
CONFIDENTIALITY = ["Public", "Internal", "Confidential", "Restricted"]
INVOICE_STATUS = ["Paid", "Pending", "Overdue", "Cancelled"]
CURRENCIES = ["USD", "EUR", "KES", "GBP"]


def gen_hr_record(fake: Faker, idx: int) -> dict:
    hire_date = fake.date_between(start_date="-15y", end_date="-1d")
    return {
        "document_type": "hr_record",
        "employee_id": f"EMP-{idx:07d}",
        "full_name": fake.name(),
        "email": fake.company_email(),
        "national_id": fake.ssn(),
        "phone": fake.phone_number(),
        "department": random.choice(DEPARTMENTS),
        "job_title": random.choice(JOB_TITLES),
        "salary": round(random.uniform(35000, 220000), 2),
        "hire_date": hire_date.isoformat(),
        "address": fake.address().replace("\n", ", "),
        "performance_rating": round(random.uniform(1.0, 5.0), 1),
        "manager_id": f"EMP-{random.randint(1, idx if idx > 1 else 1):07d}",
        "notes": fake.sentence(nb_words=12),
    }


def gen_finance_record(fake: Faker, idx: int) -> dict:
    invoice_date = fake.date_between(start_date="-3y", end_date="today")
    due_date = invoice_date + timedelta(days=random.choice([15, 30, 45, 60]))
    return {
        "document_type": "finance_invoice",
        "invoice_id": f"INV-{idx:07d}",
        "vendor_name": fake.company(),
        "amount": round(random.uniform(50, 500000), 2),
        "currency": random.choice(CURRENCIES),
        "invoice_date": invoice_date.isoformat(),
        "due_date": due_date.isoformat(),
        "status": random.choice(INVOICE_STATUS),
        "account_number": fake.iban(),
        "cost_center": f"CC-{random.randint(100, 999)}",
        "approved_by": fake.name(),
        "line_item_count": random.randint(1, 25),
        "notes": fake.sentence(nb_words=10),
    }


def gen_contract_record(fake: Faker, idx: int) -> dict:
    effective_date = fake.date_between(start_date="-5y", end_date="today")
    expiry_date = effective_date + timedelta(days=random.choice([180, 365, 730, 1095]))
    return {
        "document_type": "contract",
        "contract_id": f"CTR-{idx:07d}",
        "client_name": fake.company(),
        "contract_type": random.choice(CONTRACT_TYPES),
        "effective_date": effective_date.isoformat(),
        "expiry_date": expiry_date.isoformat(),
        "value": round(random.uniform(1000, 2_000_000), 2),
        "currency": random.choice(CURRENCIES),
        "signatory": fake.name(),
        "confidentiality_level": random.choice(CONFIDENTIALITY),
        "terms_summary": fake.paragraph(nb_sentences=3),
    }


CATEGORY_GENERATORS = {
    "hr-documents": gen_hr_record,
    "finance-documents": gen_finance_record,
    "contracts-documents": gen_contract_record,
}


def write_shards(bucket: str, generator, total_records: int, shard_size: int,
                  output_dir: str, fake: Faker) -> int:
    bucket_dir = os.path.join(output_dir, bucket)
    os.makedirs(bucket_dir, exist_ok=True)
    written = 0
    shard_idx = 0
    idx = 1
    while written < total_records:
        shard_idx += 1
        n = min(shard_size, total_records - written)
        shard_path = os.path.join(bucket_dir, f"{bucket.split('-')[0]}_shard_{shard_idx:04d}.jsonl")
        with open(shard_path, "w") as f:
            for _ in range(n):
                record = generator(fake, idx)
                f.write(json.dumps(record) + "\n")
                idx += 1
        written += n
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--records-per-category", type=int, default=40000,
                         help="Records generated per document category (x3 categories). Default 40000 (120000 total).")
    parser.add_argument("--shard-size", type=int, default=2000,
                         help="Records per shard file (= per uploaded object). Default 2000.")
    parser.add_argument("--output-dir", default=os.path.join(os.path.dirname(__file__), "output"))
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    Faker.seed(args.seed)
    random.seed(args.seed)
    fake = Faker()

    total = 0
    for bucket, generator in CATEGORY_GENERATORS.items():
        print(f"[*] Generating {args.records_per_category} records for '{bucket}'...")
        n = write_shards(bucket, generator, args.records_per_category, args.shard_size,
                          args.output_dir, fake)
        total += n
        print(f"    -> wrote {n} records")

    print(f"[+] Done. Total records generated: {total} (min required: 100000)")
    print(f"[+] Output directory: {args.output_dir}")


if __name__ == "__main__":
    main()
