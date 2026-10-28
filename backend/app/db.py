import os
from pathlib import Path
from sqlalchemy import create_engine, String, Text, ForeignKey
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
DATA = Path(os.getenv('DATA_DIR', 'backend/data'))
DATA.mkdir(parents=True, exist_ok=True)
engine = create_engine(os.getenv('DATABASE_URL',f'sqlite:///{DATA / "moimlog.db"}'),connect_args={'check_same_thread':False})
SessionLocal = sessionmaker(engine, expire_on_commit=False)
class Base(DeclarativeBase): pass
class User(Base):
    __tablename__='users'
    id: Mapped[str] = mapped_column(String,primary_key=True)
    email: Mapped[str] = mapped_column(String,unique=True)
    password: Mapped[str] = mapped_column(String)
    settings: Mapped[str] = mapped_column(Text,default='{}')
class AuthSession(Base):
    __tablename__='sessions'
    token: Mapped[str] = mapped_column(String,primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'))
    expires: Mapped[int]
class Meeting(Base):
    __tablename__='meetings'
    id: Mapped[str] = mapped_column(String,primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id'),index=True)
    data: Mapped[str] = mapped_column(Text)
    updated: Mapped[int]
Base.metadata.create_all(engine)
