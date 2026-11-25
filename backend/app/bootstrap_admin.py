"""Initialize the single administrator from an interactive operator console."""
import argparse
import getpass
import re
import uuid

from dotenv import load_dotenv

load_dotenv()

from pwdlib import PasswordHash
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from .db import Administrator, SessionLocal, User


def bootstrap(email: str, password: str | None = None) -> None:
    email = email.strip().lower()
    if len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        raise ValueError("이메일을 확인해 주세요.")
    with SessionLocal() as db:
        if db.get(Administrator, 1):
            raise ValueError("관리자가 이미 설정되어 있습니다.")
        user = db.scalar(select(User).where(User.email == email))
        if password is None:
            if user is None:
                raise ValueError("기존 계정을 찾을 수 없습니다.")
        else:
            if user is not None or not 10 <= len(password) <= 128:
                raise ValueError("새 이메일과 10~128자 비밀번호를 사용하세요.")
            user = User(id=str(uuid.uuid4()), email=email,
                        password=PasswordHash.recommended().hash(password),
                        settings='{"name":"운영 관리자","retentionDays":90}')
            db.add(user)
        db.add(Administrator(slot=1, user_id=user.id))
        try:
            db.commit()
        except IntegrityError:
            raise ValueError("관리자 또는 계정이 이미 생성되었습니다.") from None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("email")
    parser.add_argument("--existing", action="store_true", help="지정한 기존 계정을 관리자로 설정")
    args = parser.parse_args()
    password = None
    if not args.existing:
        password = getpass.getpass("새 관리자 비밀번호: ")
        if password != getpass.getpass("비밀번호 확인: "):
            parser.exit(1, "비밀번호가 일치하지 않습니다.\n")
    try:
        bootstrap(args.email, password)
    except ValueError as exc:
        parser.exit(1, f"{exc}\n")
    print("관리자 설정 완료")


if __name__ == "__main__":
    main()
