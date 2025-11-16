#!/usr/bin/env node

/**
 * Script to generate and store voice preview audio files
 * Automatically detects new voices and generates missing previews
 * 
 * Usage: 
 *   node scripts/generate-voice-previews.js        # Generate all missing previews
 *   node scripts/generate-voice-previews.js --all   # Regenerate all previews
 */

import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import https from 'https';
import fs from 'fs';
import { promisify } from 'util';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables
config({ path: join(__dirname, '..', '.env') });

const writeFile = promisify(fs.writeFile);
const mkdir = promisify(fs.mkdir);
const readdir = promisify(fs.readdir);
const readFile = promisify(fs.readFile);

/**
 * Load voice configuration from JSON file
 * This is the single source of truth for available voices
 */
async function loadVoiceConfig() {
  const configPath = join(__dirname, '..', 'voice-config.json');
  try {
    const configData = await readFile(configPath, 'utf8');
    const config = JSON.parse(configData);
    return {
      previewText: config.previewText || "Hello, this is a preview of my voice. How do I sound?",
      voices: config.voices || []
    };
  } catch (error) {
    console.error(`❌ Failed to load voice-config.json: ${error.message}`);
    console.error('   Falling back to hardcoded voices...\n');
    // Fallback to hardcoded voices if config file doesn't exist
    return {
      previewText: "Hello, this is a preview of my voice. How do I sound?",
      voices: [
        { id: 'cartesia-coral', tts: 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc', provider: 'cartesia' },
        { id: 'cartesia-breeze', tts: 'cartesia/sonic-3:b5c0c5c5-5c5c-5c5c-5c5c-5c5c5c5c5c5c', provider: 'cartesia' },
        { id: 'cartesia-ember', tts: 'cartesia/sonic-3:c6d1d6d6-d6d6-d6d6-d6d6-d6d6d6d6d6d6', provider: 'cartesia' },
        { id: 'cartesia-nova', tts: 'cartesia/sonic-3:d7e2e7e7-e7e7-e7e7-e7e7-e7e7e7e7e7e7', provider: 'cartesia' },
        { id: 'cartesia-zen', tts: 'cartesia/sonic-3:e8f3f8f8-f8f8-f8f8-f8f8-f8f8f8f8f8f8', provider: 'cartesia' },
        { id: 'elevenlabs-rachel', tts: 'elevenlabs/eleven_turbo_v2_5:21m00Tcm4TlvDq8ikWAM', provider: 'elevenlabs' },
        { id: 'elevenlabs-domi', tts: 'elevenlabs/eleven_turbo_v2_5:AZnzlk1XvdvUeBnXmlld', provider: 'elevenlabs' },
        { id: 'elevenlabs-bella', tts: 'elevenlabs/eleven_turbo_v2_5:EXAVITQu4vr4xnSDxMaL', provider: 'elevenlabs' },
        { id: 'elevenlabs-josh', tts: 'elevenlabs/eleven_turbo_v2_5:TxGEqnHWrfWFTfGW9XjX', provider: 'elevenlabs' },
        { id: 'elevenlabs-arnold', tts: 'elevenlabs/eleven_turbo_v2_5:VR6AewLTigWG4xSOukaG', provider: 'elevenlabs' },
        { id: 'elevenlabs-adam', tts: 'elevenlabs/eleven_turbo_v2_5:pNInz6obpgDQGcFmaJgB', provider: 'elevenlabs' },
      ]
    };
  }
}

/**
 * Check which previews already exist
 */
async function getExistingPreviews(previewsDir) {
  if (!fs.existsSync(previewsDir)) {
    return new Set();
  }
  
  const files = await readdir(previewsDir);
  return new Set(files.map(file => {
    // Remove extension: "cartesia-coral.m4a" -> "cartesia-coral"
    return file.replace(/\.(m4a|mp3)$/, '');
  }));
}

/**
 * Get voices that need preview generation
 */
function getVoicesToGenerate(voices, existingPreviews, regenerateAll = false) {
  if (regenerateAll) {
    return voices;
  }
  
  return voices.filter(voice => !existingPreviews.has(voice.id));
}

async function generatePreview(voice, previewText) {
  // Parse TTS identifier
  const [modelPart, voiceId] = voice.tts.split(':');
  const [provider, model] = modelPart.split('/');

  if (provider === 'cartesia') {
    return generateCartesiaPreview(voiceId, previewText);
  } else if (provider === 'elevenlabs') {
    return generateElevenLabsPreview(voiceId, previewText);
  } else {
    throw new Error(`Unsupported provider: ${provider}`);
  }
}

async function generateCartesiaPreview(voiceId, text) {
  const apiKey = process.env.CARTESIA_API_KEY;
  if (!apiKey) {
    throw new Error('CARTESIA_API_KEY not configured');
  }

  const requestBody = {
    model_id: 'sonic-3',
    voice: {
      mode: 'id',
      id: voiceId
    },
    transcript: text,
    language: 'en',
    output_format: {
      container: 'wav',
      encoding: 'pcm_s16le',
      sample_rate: 44100
    }
  };

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.cartesia.ai',
      port: 443,
      path: '/tts/bytes',
      method: 'POST',
      headers: {
        'X-API-Key': apiKey,
        'Cartesia-Version': '2024-06-10',
        'Content-Type': 'application/json',
      }
    };

    const req = https.request(options, (response) => {
      if (response.statusCode !== 200) {
        let errorBody = '';
        response.on('data', (chunk) => { errorBody += chunk; });
        response.on('end', () => {
          reject(new Error(`Cartesia API error ${response.statusCode}: ${errorBody}`));
        });
        return;
      }

      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        resolve(Buffer.concat(chunks));
      });
    });

    req.on('error', reject);
    req.write(JSON.stringify(requestBody));
    req.end();
  });
}

async function generateElevenLabsPreview(voiceId, text) {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) {
    throw new Error('ELEVENLABS_API_KEY not configured - skipping ElevenLabs voices');
  }

  const requestBody = {
    text: text,
    model_id: 'eleven_turbo_v2_5',
    voice_settings: {
      stability: 0.5,
      similarity_boost: 0.75
    }
  };

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.elevenlabs.io',
      port: 443,
      path: `/v1/text-to-speech/${voiceId}`,
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
      }
    };

    const req = https.request(options, (response) => {
      if (response.statusCode !== 200) {
        let errorBody = '';
        response.on('data', (chunk) => { errorBody += chunk; });
        response.on('end', () => {
          reject(new Error(`ElevenLabs API error ${response.statusCode}: ${errorBody}`));
        });
        return;
      }

      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        resolve(Buffer.concat(chunks));
      });
    });

    req.on('error', reject);
    req.write(JSON.stringify(requestBody));
    req.end();
  });
}

async function main() {
  const regenerateAll = process.argv.includes('--all') || process.argv.includes('-a');
  
  console.log('🎙️  Voice Preview Generator\n');
  console.log(`Mode: ${regenerateAll ? 'Regenerate all previews' : 'Generate missing previews only'}\n`);
  
  // Load voice configuration
  const config = await loadVoiceConfig();
  const VOICES = config.voices;
  const PREVIEW_TEXT = config.previewText;
  
  if (VOICES.length === 0) {
    console.error('❌ No voices found in configuration!');
    console.error('   Please check voice-config.json or add voices to the script.');
    process.exit(1);
  }
  
  console.log(`📝 Loaded ${VOICES.length} voice(s) from configuration\n`);
  
  // Create previews directory
  const previewsDir = join(__dirname, '..', 'public', 'voice-previews');
  try {
    await mkdir(previewsDir, { recursive: true });
    console.log(`✅ Directory ready: ${previewsDir}\n`);
  } catch (error) {
    if (error.code !== 'EEXIST') {
      throw error;
    }
  }
  
  // Check existing previews
  const existingPreviews = await getExistingPreviews(previewsDir);
  const voicesToGenerate = getVoicesToGenerate(VOICES, existingPreviews, regenerateAll);
  
  if (voicesToGenerate.length === 0) {
    console.log('✅ All voice previews already exist!');
    console.log(`   Total voices: ${VOICES.length}`);
    console.log(`   Existing previews: ${existingPreviews.size}`);
    console.log('\n💡 To regenerate all previews, run: npm run generate-previews -- --all');
    return;
  }
  
  console.log(`📋 Found ${voicesToGenerate.length} voice(s) to generate:\n`);
  voicesToGenerate.forEach(voice => {
    console.log(`   - ${voice.id} (${voice.name || voice.id})`);
  });
  console.log('');
  
  let successCount = 0;
  let failCount = 0;
  
  for (const voice of voicesToGenerate) {
    try {
      console.log(`🎵 Generating preview for ${voice.id}...`);
      const audioData = await generatePreview(voice, PREVIEW_TEXT);
      
      // Determine file extension based on provider
      const extension = voice.provider === 'cartesia' ? 'wav' : 'mp3';
      const filePath = join(previewsDir, `${voice.id}.${extension}`);
      
      await writeFile(filePath, audioData);
      console.log(`   ✅ Generated: ${voice.id}.${extension} (${(audioData.length / 1024).toFixed(2)} KB)\n`);
      successCount++;
    } catch (error) {
      console.error(`   ❌ Failed: ${error.message}\n`);
      failCount++;
    }
  }
  
  console.log('\n📊 Summary:');
  console.log(`   ✅ Success: ${successCount}`);
  console.log(`   ❌ Failed: ${failCount}`);
  console.log(`   📁 Location: ${previewsDir}`);
  console.log(`   📦 Total previews: ${existingPreviews.size + successCount}`);
  
  if (successCount > 0) {
    console.log('\n💡 Next steps:');
    console.log('   1. Commit the new preview files to git (or upload to Railway/CDN)');
    console.log('   2. Deploy to production');
    console.log('   3. Users will automatically see new voices with previews');
  }
}

main().catch(console.error);

