import crypto from 'crypto';

interface EncryptedToken {
  ciphertext: string;
  iv: string;
  tag: string;
}

const deriveKey = (): Buffer => {
  const secret = process.env.SYNC_SETTINGS_SECRET;
  if (!secret || secret.trim().length < 16) {
    throw new Error('SYNC_SETTINGS_SECRET is not configured');
  }
  return crypto.createHash('sha256').update(secret).digest();
};

export const encryptToken = (plain: string): EncryptedToken => {
  if (plain.trim().length === 0) {
    return { ciphertext: '', iv: '', tag: '' };
  }

  const key = deriveKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([
    cipher.update(plain, 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return {
    ciphertext: encrypted.toString('base64'),
    iv: iv.toString('base64'),
    tag: tag.toString('base64'),
  };
};

export const decryptToken = (
  ciphertext: string | null,
  iv: string | null,
  tag: string | null,
): string => {
  if (!ciphertext || !iv || !tag) return '';

  const key = deriveKey();
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(iv, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(tag, 'base64'));
  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(ciphertext, 'base64')),
    decipher.final(),
  ]);
  return decrypted.toString('utf8');
};
