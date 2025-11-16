#!/usr/bin/env node
// Quick script to check if environment variables are loaded correctly

import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

console.log('🔍 Checking environment variables...\n');

const envResult = config({ path: join(__dirname, '.env') });

if (envResult.error) {
  console.error('❌ Error loading .env:', envResult.error.message);
  process.exit(1);
}

console.log('✅ .env file loaded\n');

const requiredVars = [
  'LIVEKIT_API_KEY',
  'LIVEKIT_API_SECRET',
  'LIVEKIT_URL'
];

let allPresent = true;

for (const varName of requiredVars) {
  const value = process.env[varName];
  if (value) {
    if (varName.includes('SECRET')) {
      console.log(`✅ ${varName}: SET (${value.length} chars)`);
    } else if (varName.includes('KEY')) {
      console.log(`✅ ${varName}: ${value.slice(0, 6)}... (${value.length} chars)`);
    } else {
      console.log(`✅ ${varName}: ${value}`);
    }
  } else {
    console.error(`❌ ${varName}: NOT SET`);
    allPresent = false;
  }
}

console.log('');

if (allPresent) {
  console.log('✅ All required environment variables are present!');
  console.log('\n💡 If you still get errors, try:');
  console.log('   1. Restart the server: npm start');
  console.log('   2. Check for whitespace in .env file');
  console.log('   3. Ensure .env is in the backend/ directory');
} else {
  console.error('❌ Some environment variables are missing!');
  console.error('   Please check your .env file.');
  process.exit(1);
}

