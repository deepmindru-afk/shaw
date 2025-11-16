import OpenAI from 'openai';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

const voices = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
const previewText = "Hi, I'm your AI assistant. I'm here to help you with whatever you need.";

async function generateVoicePreviews() {
  const outputDir = path.join(__dirname, 'public', 'voice-previews');

  // Create directory if it doesn't exist
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  console.log('Generating OpenAI Realtime voice previews...\n');

  for (const voice of voices) {
    try {
      console.log(`Generating preview for: ${voice}`);

      const mp3 = await openai.audio.speech.create({
        model: 'tts-1',
        voice: voice,
        input: previewText,
        speed: 1.0
      });

      const buffer = Buffer.from(await mp3.arrayBuffer());
      const outputPath = path.join(outputDir, `openai-${voice}.mp3`);

      fs.writeFileSync(outputPath, buffer);
      console.log(`✅ Saved: openai-${voice}.mp3 (${buffer.length} bytes)\n`);
    } catch (error) {
      console.error(`❌ Failed to generate ${voice}:`, error.message);
    }
  }

  console.log('Done! Generated all OpenAI Realtime voice previews.');
}

generateVoicePreviews().catch(console.error);
