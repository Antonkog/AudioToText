# Third-party notices

AudioToText uses the following open-source components and model assets. Their licenses remain separate from AudioToText's MIT license.

## Argmax OSS / WhisperKit / TTSKit

- Project: <https://github.com/argmaxinc/argmax-oss-swift>
- License: MIT
- Purpose: local Core ML transcription and speech generation.

## Whisper model assets

- Project: <https://huggingface.co/argmaxinc/whisperkit-coreml>
- Runtime mirror: <https://huggingface.co/RedHotAnton/whisperkit-coreml>
- Origin: OpenAI Whisper
- Purpose: downloaded on demand for local speech recognition.

## Qwen3-TTS model assets

- Core ML assets: <https://huggingface.co/argmaxinc/ttskit-coreml>
- Core ML runtime mirror: <https://huggingface.co/RedHotAnton/ttskit-coreml>
- Tokenizer runtime mirror: <https://huggingface.co/RedHotAnton/Qwen3-0.6B>
- Original models: <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice>
- Original Qwen model license: Apache License 2.0
- The upstream Core ML asset repository does not currently declare a separate model-card license.
- Purpose: downloaded on demand for local text-to-speech generation.

## LAME 4.0

- Project: <https://lame.sourceforge.io/>
- Source: <https://sourceforge.net/projects/lame/files/lame/4.0/lame-4.0.tar.gz/download>
- License: GNU Lesser General Public License (LGPL)
- Purpose: MP3 export.

The packaged application invokes the unmodified LAME command-line program as a separate executable. Its license file is included in the application bundle at `Contents/Resources/Licenses/LAME-LGPL.txt`.
