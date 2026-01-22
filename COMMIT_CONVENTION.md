# Commit Convention Guide

이 프로젝트는 **Conventional Commits** 규칙을 따릅니다.
커밋 메시지는 다음과 같은 형식을 사용해 주세요.

```text
<type>(<scope>): <subject>

<body> (옵션)

<footer> (옵션)
```

---

## 1. Type (필수)
변경 사항의 종류를 나타냅니다.

*   **feat**: 새로운 기능 추가 (Features)
*   **fix**: 버그 수정 (Bug Fixes)
*   **docs**: 문서 수정 (Documentation)
*   **style**: 코드 포맷팅, 세미콜론 누락 등 코드 변경이 없는 경우 (Styles)
*   **refactor**: 코드 리팩토링 (기능 변경 없음)
*   **test**: 테스트 코드 추가 또는 수정
*   **chore**: 빌드 업무 수정, 패키지 매니저 설정 등 (프로덕션 코드 변경 없음)
*   **perf**: 성능 개선
*   **ci**: CI 설정 파일 수정

## 2. Scope (선택)
변경 사항이 적용된 범위를 괄호 안에 명시합니다.
예: `feat(auth): 로그인 기능 추가`, `fix(ui): 버튼 색상 수정`

## 3. Subject (필수)
변경 사항에 대한 간략한 설명을 작성합니다.
*   명령문, 현재 시제로 작성 (예: "change" O, "changed" X)
*   첫 글자는 소문자로 시작 (영문 작성 시)
*   끝에 마침표(.)를 찍지 않음
*   한글 작성 시 간결하게 핵심만 요약

## 4. 예시 (Examples)

**기능 추가:**
```
feat(chat): 이미지 전송 기능 추가
```

**버그 수정:**
```
fix: 앱 실행 시 크래시 발생하는 문제 수정
```

**문서 수정:**
```
docs: README 파일 사용법 업데이트
```
