from typing import Literal
from datetime import date
from pydantic import BaseModel, Field, model_validator

class Participant(BaseModel):
    id: str = Field(min_length=1, max_length=80)
    name: str = Field(min_length=1, max_length=60)

class MeetingInput(BaseModel):
    meetingDate: date
    leader: str = Field(min_length=1, max_length=60)
    title: str = Field(default='', max_length=200)
    sermonTitle: str = Field(default='', max_length=200)
    question: str = Field(default='', max_length=2000)
    participants: list[Participant] = Field(min_length=1, max_length=50)
    step: int = Field(default=1, ge=1, le=7)
    @model_validator(mode='after')
    def unique(self):
        if len({p.id for p in self.participants}) != len(self.participants):
            raise ValueError('참석자 ID는 고유해야 합니다.')
        return self

class Sharing(BaseModel):
    participantId: str
    name: str
    sermonSharing: str
    lifeSharing: str
    prayerRequests: str
    prayerSource: Literal['explicit', 'inferred', 'none']
    needsReview: bool
    warnings: list[str]
    sunday: Literal['unknown','yes','no'] = 'unknown'
    youth: Literal['unknown','yes','no'] = 'unknown'
    meeting: Literal['unknown','yes','no'] = 'unknown'
    qt: Literal['unknown','yes','no'] = 'unknown'

class Report(BaseModel):
    meetingDate: str
    leader: str
    meetingSummary: str
    participants: list[Sharing]
    unassignedStatements: list[str]
    warnings: list[str]

class ReportUpdate(BaseModel):
    report: Report
    complete: bool = False

class TranscriptInput(BaseModel):
    text: str = Field(min_length=1, max_length=1000000)

class SpeakerInput(BaseModel):
    mapping: dict[str, str | None]

class AnalysisInput(BaseModel):
    mode: Literal['ai','local'] = 'ai'
    consent: bool = False

class Credentials(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=10, max_length=128)
    name: str = Field(default='순장님', max_length=60)

class SettingsInput(BaseModel):
    name: str = Field(min_length=1,max_length=60)
    community: str = Field(default='',max_length=100)
    isLeader: bool = True
    members: list[str] = Field(default_factory=list,max_length=50)
    retentionDays: int = Field(default=90,ge=1,le=365)
