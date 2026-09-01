package main

import (
	"bytes"
	"context"
	"fmt"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// Store is where a report ends up.
//
// An interface so the handler can be tested without a bucket, and so that
// moving to another provider's object storage is a constructor rather than a
// rewrite.
type Store interface {
	Put(ctx context.Context, key string, body []byte) error
}

// ObjectStore writes one JSON object per report to an S3-compatible bucket.
//
// Object storage rather than a database, because a report is a document and
// the volume is single digits a week. No migrations, nothing to patch, nothing
// running when nobody is reporting anything. If aggregation ever matters the
// bucket can be pulled and queried locally, which is a better trade than
// keeping a database alive for queries nobody has written yet.
type ObjectStore struct {
	client *minio.Client
	bucket string
}

func NewObjectStore(endpoint, region, bucket, accessKey, secretKey string) (*ObjectStore, error) {
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: true,
		Region: region,
	})
	if err != nil {
		return nil, fmt.Errorf("object storage client: %w", err)
	}
	return &ObjectStore{client: client, bucket: bucket}, nil
}

func (s *ObjectStore) Put(ctx context.Context, key string, body []byte) error {
	_, err := s.client.PutObject(
		ctx,
		s.bucket,
		key,
		bytes.NewReader(body),
		int64(len(body)),
		minio.PutObjectOptions{ContentType: "application/json"},
	)
	if err != nil {
		return fmt.Errorf("writing %s: %w", key, err)
	}
	return nil
}

// StorageKey is where a report lives in the bucket.
//
// Dated path first so a listing is browsable by hand and a lifecycle rule can
// expire a whole month; the reference last so the string a caregiver quotes is
// the string that finds the file.
func StorageKey(at time.Time, kind, reference string) string {
	return fmt.Sprintf("%s/%s/%s.json", at.UTC().Format("2006/01/02"), kind, reference)
}
