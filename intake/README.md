# wordbridge report intake

Takes the report a caregiver read and pressed send on, writes it to object
storage, and emails to say one arrived. One endpoint, no database, no session,
no cookie.

The wire format is `docs/reporting.md`. It lives in this repo rather than its
own so the format and the thing that parses it cannot drift.

## What it does, in order

1. `POST /v1/reports`, bearer token, at most 64 KB.
2. Validate far enough to know it is a report. Refuse what cannot be filed.
3. Write the bytes that arrived to `s3://…/2026/09/01/bug/WB-7QK2.json`.
4. Email the note, the device and the reference. Not the stack trace.
5. Answer `202 {"reference":"WB-7QK2"}`.

**Store before notify, notify before answer.** The app tells a caregiver "sent"
on a 202, so a 202 has to mean the report is somewhere durable. Mail failing is
logged and does not fail the request; storage failing returns 503 and the app
keeps the report for another try.

**Stores the bytes that arrived, not a re-encoding of them.** The app owns the
wire format and will add fields to it. A server that unmarshalled into an
exhaustive struct and wrote that back would drop anything it had not been
taught, and would need releasing in step with the app — which is what the
`schema` number exists to avoid.

## Running it

```sh
go test ./...
go run .
```

| Variable | | |
|---|---|---|
| `INTAKE_TOKEN` | required | Matches `WORDBRIDGE_INTAKE_TOKEN` in the app build |
| `S3_ENDPOINT` | required | e.g. `s3.fr-par.scw.cloud` |
| `S3_BUCKET` | required | |
| `S3_ACCESS_KEY` `S3_SECRET_KEY` | required | |
| `S3_REGION` | `fr-par` | |
| `SMTP_HOST` `MAIL_TO` `MAIL_FROM` | optional | All three or no mail at all |
| `SMTP_PORT` | `587` | |
| `SMTP_USER` `SMTP_PASS` | optional | |
| `PORT` | `8080` | |

A deployment with no mail settings is a valid one: reports are still taken and
still stored, and somebody reads the bucket. Refusing to start over a missing
mail password would trade every report for a setting.

**There is no default token.** An intake with no token would take anything from
anybody, so it refuses to start without one.

## Deploying

### Its own organisation, first

Not a project inside an existing one. A Scaleway **organisation** is the
billing and IAM boundary, and this one holds reports about disabled children's
communication devices and an API key that can write to them. It does not belong
next to anything else, and if wordbridge ever becomes an entity of its own the
organisation goes with it.

Inside that organisation, make a **named project** — not the default one. The
Terraform refuses the default: in Scaleway an organisation's default project
carries the organisation's own id, so comparing the two catches both deploying
into the wrong organisation entirely and deploying into the right one's
default.

The `scw` CLI profile on a machine that has other Scaleway work on it points
somewhere else, and the provider block names the organisation rather than
inheriting it for that reason. Use a separate profile:

```sh
scw init --profile wordbridge
export SCW_PROFILE=wordbridge
```

### Then

```sh
docker build -t rg.fr-par.scw.cloud/wordbridge/intake:$(git rev-parse --short HEAD) .
docker push rg.fr-par.scw.cloud/wordbridge/intake:…

cd deploy
terraform init
terraform apply \
  -var organization_id=… -var project_id=… -var image=… \
  -var intake_token=… \
  -var mail_to=… -var mail_from=… -var smtp_user=… -var smtp_password=…
```

⚠️ **The state file holds the object storage secret key in clear.** It is
gitignored, which is not the same as safe. Put it on a remote backend or an
encrypted volume before this is anything other than a first deploy.

`terraform output intake_url` is what the app build wants:

```sh
flutter build ipa \
  --dart-define=WORDBRIDGE_INTAKE_URL=https://…/v1/reports \
  --dart-define=WORDBRIDGE_INTAKE_TOKEN=…
```

A build given neither has no reporting, and the Reports screen says so rather
than offering a button that cannot work. That is the correct state for a fork
and for anyone building from source.

## What it will not do

- **Follow a redirect.** The client does not, on purpose: a redirect is a way
  for an intake to be repointed at somewhere nobody agreed to.
- **Write an address down.** The rate limiter holds one in memory for as long
  as it needs and drops it when it goes quiet. Nothing about the caller is
  stored beside the report.
- **Set a cookie, or anything else that would tie two reports together.**
- **Read a report back.** The container's credentials are write only, so a
  compromised container cannot enumerate what other people have sent.

## Scale, and why it is shaped like this

Realistic volume is single digits a week. That fact drives every decision here:
object storage rather than a database, scale to zero rather than a VM, and an
in-process rate limiter rather than a shared one. What actually caps abuse is
`max_scale = 2` in the Terraform; the limiter stops one client filling that.

If reports ever arrive fast enough for that to be wrong, the shape to move to
is a queue, not a bigger container.
