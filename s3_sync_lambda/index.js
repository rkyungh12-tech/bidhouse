const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { BlobServiceClient, StorageSharedKeyCredential } = require('@azure/storage-blob');

exports.handler = async (event) => {
  const s3 = new S3Client({ region: 'ap-northeast-2' });

  const accountName = process.env.AZ_STORAGE_ACCOUNT_NAME;
  const accountKey  = process.env.AZ_STORAGE_ACCOUNT_KEY;
  const credential  = new StorageSharedKeyCredential(accountName, accountKey);
  const blobService = new BlobServiceClient(
    `https://${accountName}.blob.core.windows.net`,
    credential
  );
  const container = blobService.getContainerClient('uploads');

  for (const record of event.Records) {
    const bucket  = record.s3.bucket.name;
    const s3Key   = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));

    const { Body } = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: s3Key }));
    const blockBlob = container.getBlockBlobClient(s3Key);
    const chunks = [];
    for await (const chunk of Body) chunks.push(chunk);
    const buffer = Buffer.concat(chunks);
    await blockBlob.upload(buffer, buffer.length);
    console.log(`✅ 복사 완료: ${s3Key}`);
  }
};