import os

def text_model():
    model=os.getenv('GROQ_TEXT_MODEL','openai/gpt-oss-120b')
    if model != 'openai/gpt-oss-120b':
        raise ValueError('허용되지 않은 Groq 텍스트 모델입니다. openai/gpt-oss-120b를 설정해 주세요.')
    return model
