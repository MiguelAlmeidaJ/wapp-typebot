import sys
import speech_recognition as sr

def transcribe(audio_file_path):
    recognizer = sr.Recognizer()

    with sr.AudioFile(audio_file_path) as source:
        audio = recognizer.record(source)

    try:
        transcription = recognizer.recognize_google(audio, language='pt-BR')
        return transcription
    except sr.UnknownValueError:
        return "Google Speech Recognition could not understand audio"
    except sr.RequestError as e:
        return f"Could not request results from Google Speech Recognition service; {e}"

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python transcribe.py path_to_audio_file")
        sys.exit(1)

    audio_file_path = sys.argv[1]
    print(transcribe(audio_file_path))
