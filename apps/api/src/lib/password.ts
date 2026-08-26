import {
  randomBytes,
  scrypt as nodeScrypt,
  timingSafeEqual
} from "node:crypto";

const KEY_LENGTH = 64;
const SCRYPT_OPTIONS = {
  N: 16_384,
  r: 8,
  p: 1,
  maxmem: 64 * 1024 * 1024
};

function deriveKey(password: string, salt: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    nodeScrypt(
      password,
      salt,
      KEY_LENGTH,
      SCRYPT_OPTIONS,
      (error, derivedKey) => {
        if (error) {
          reject(error);
          return;
        }

        resolve(derivedKey as Buffer);
      }
    );
  });
}

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16).toString("hex");
  const hash = await deriveKey(password, salt);

  return `scrypt$${salt}$${hash.toString("hex")}`;
}

export async function verifyPassword(
  password: string,
  storedPassword: string
): Promise<boolean> {
  const [algorithm, salt, storedHash] = storedPassword.split("$");

  if (algorithm !== "scrypt" || !salt || !storedHash) {
    return false;
  }

  const candidate = await deriveKey(password, salt);
  const expected = Buffer.from(storedHash, "hex");

  if (candidate.length !== expected.length) {
    return false;
  }

  return timingSafeEqual(candidate, expected);
}
