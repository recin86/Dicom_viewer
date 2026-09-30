# DICOM Viewer 에이전트 개발 운영

작성일 2026-09-30. 프로젝트의 에이전트 지침과 역할·스킬 사용 방법을 설명한다. 제품 범위와 기술 채택 상태는 기존 제품 문서와 ADR이 관리한다. 이 구성의 작성은 P0 실험, 앱 구현 또는 DICOM 호환성 검증의 완료를 뜻하지 않는다.

## 파일과 적용 범위

| 위치 | 역할 |
| --- | --- |
| [AGENTS.md](../AGENTS.md) | 모든 작업의 공통 규칙, 위임 조건, 작성권과 완료 판정 |
| [.codex/config.toml](../.codex/config.toml) | 서브에이전트 활성화와 동시 실행 상한 3개; 메인 제외 |
| `.codex/agents/*.toml` | 프로젝트 전용 커스텀 역할의 이름·설명·지침 |
| `.agents/skills/*/SKILL.md` | 작업에 따라 읽는 전용 절차와 판단 규칙 |
| `.agents/skills/*/agents/openai.yaml` | 스킬 목록에 표시할 이름·설명·기본 호출 문장 |
| `docs/implementation/<단계>-<주제>.md` | 개발할 때 메인이 작성하는 배정·결정·시험 증거; 아직 실행 계획을 생성하지 않음 |

프로젝트 파일만 사용한다. 전역 Codex 설정, 인증, 모델과 개발자 계정을 변경하지 않는다. 역할별 모델/추론 설정을 지정하지 않았으며 실제 모델은 부모와 사용자의 기존 서브에이전트 설정을 따른다. 각 역할은 항상 실행되는 서비스가 아니라 필요한 작업에 호출하는 지침이다.

## 역할과 스킬

| 담당 | 역할 설정 | 기본 스킬 | 경계 |
| --- | --- | --- | --- |
| 메인 | 현재 개발 채팅 | [dicom-orchestrate](../.agents/skills/dicom-orchestrate/SKILL.md), 계약 변경 시 [dicom-ffi-contract](../.agents/skills/dicom-ffi-contract/SKILL.md) | 공유 계약·빌드·문서·통합·완료 판정 |
| Rust 코어 | [dicom_core](../.codex/agents/dicom_core.toml) | [dicom-core](../.agents/skills/dicom-core/SKILL.md) | 배정된 코어 모듈·시험; FFI·공통 의존성은 메인에 요청 |
| macOS 앱 | [macos_app](../.codex/agents/macos_app.toml) | [dicom-macos](../.agents/skills/dicom-macos/SKILL.md) | 배정된 Swift·shader·앱 시험; Xcode target·생성 바인딩은 메인에 요청 |
| 시험 자료 | [dicom_fixtures](../.codex/agents/dicom_fixtures.toml) | [dicom-fixtures](../.agents/skills/dicom-fixtures/SKILL.md) | 합성 자료·manifest·독립 기대값·배정된 시험 |
| 독립 리뷰 | [dicom_reviewer](../.codex/agents/dicom_reviewer.toml) | [dicom-review](../.agents/skills/dicom-review/SKILL.md) | 읽기 전용 판단·결함·재현 방법; 구현·golden 수정 없음 |

시험 자료 작성과 독립 리뷰는 역할을 분리한다. 리뷰 역할은 `sandbox_mode = "read-only"`를 요청하고 지침으로도 수정을 금지한다. 부모 세션의 실행 중 권한 설정이 커스텀 설정을 override할 수 있으므로, 설정만으로 실제 격리가 보장됐다고 판단하지 않는다.

## 사용하기

프로젝트 설정을 읽는 새 Codex 개발 채팅에서 시작한다. 설정·스킬은 클라이언트의 버전, 프로젝트 신뢰 설정과 시작 디렉터리에 따라 적용된다. 생성한 파일이 현재 채팅에 즉시 다시 로드됐다고 가정하지 않는다.

다음 요청으로 적용 상태를 확인할 수 있다.

```text
이 프로젝트의 AGENTS.md를 읽고 현재 발견한 커스텀 역할과 프로젝트 스킬을 확인해줘.
아직 제품 구현은 시작하지 말고 역할 호출 가능 여부와 설정 적용 범위를 설명해줘.
```

역할 호출을 지원하는 클라이언트는 커스텀 역할 이름으로 호출한다. 현재 도구가 일반 서브에이전트만 지원하면 메인이 역할 TOML의 지침과 스킬 경로를 읽어 작업 배정에 전달한다. 이 경우 파일 기반 역할의 자동 로드와 수동 위임을 구분해 보고한다.

개발을 시작할 때 사용할 요청 예시:

```text
$dicom-orchestrate를 사용해서 P0 기술 검증부터 시작해줘.
독립 과업을 dicom_core, macos_app, dicom_fixtures 역할에 나누고,
공유 API와 빌드는 메인이 맡아줘. 완료 후 dicom_reviewer로 독립 검토해줘.
실제 버전·환경·자료와 실험 결과를 기록하고 P0 종료 조건을 확인해줘.
```

이 예시는 개발을 시작하라는 별도의 요청에 사용한다. 지침 생성 작업이 위 요청을 실행한 것으로 해석되지는 않는다.

## 단계에 따른 분담

| 단계 | 메인의 확인·통합 | 병렬로 맡길 수 있는 작업 |
| --- | --- | --- |
| P0 | 환경·연결·버퍼 왕복과 OQ/ADR 결정 근거 | 코어 decoder/feature 실험, 앱 표시 경로 조사, fixture와 독립 기대값 준비 |
| P1 | 픽셀 계약과 실제 한 프레임의 종단 연결 | 코어 adapter, 앱 viewport, 픽셀·VOI·좌표 기준 시험 |
| P2 | 프레임·generation·캐시 계약과 통합 | 코어 grouping/engine, 탐색·cine UI, 취소·자원 시험 |
| P3 | OQ-07/08 확인과 측정 계약 | F64 측정, 주석·비교 UI, 보정·ROI 기준 시험 |
| P4 | 영속 참조·저장 snapshot과 복구 계약 | 코어 저장/재연결/CSV, 앱 dirty·복원·PNG, 충돌·실패 시험 |
| P5 | OQ-09와 배포 방식, release 빌드·지원 판정 | 설치 자료·수행 가능한 대상 환경 시험, 제한·결함 검토 |

서로 기다리는 producer/consumer를 완전히 독립된 작업으로 배정하지 않는다. 공유 타입 변경은 메인이 관리하고, 실제 수정할 파일 목록과 계약 revision을 배정한다. [작업 배정 양식](../.agents/skills/dicom-orchestrate/assets/task-brief.md)과 [단계 계획 양식](../.agents/skills/dicom-orchestrate/assets/stage-plan.md)을 사용할 수 있다.

## 설정과 스킬 검사

프로젝트 루트에서 다음을 실행한다.

```sh
python3 .agents/skills/dicom-orchestrate/scripts/validate_setup.py
```

검사에는 PyYAML과 Python 3.11 이상의 tomllib 또는 그 이전 버전의 tomli가 필요하다. 검사 스크립트는 의존성을 설치하거나 설정을 변경하지 않고, 파일을 읽어 TOML/YAML·역할/스킬 연결·로컬 링크를 확인한다. 이는 앱 시험과 실제 커스텀 역할 호출 시험이 아니다.

실제 로컬 CLI에 `debug prompt-input`이 있으면 프로젝트 루트에서 모델 호출 없이 지침 발견을 추가 확인할 수 있다. 이 출력에는 전역 지침도 포함될 수 있으므로 전체를 저장소나 일반 로그에 복사하지 않는다. 필요한 프로젝트 이름과 적용 여부만 확인한다.

독립 리뷰에서는 P0 배정, 공유 타입 변경, golden 불일치, 환경 미준비, 읽기 전용 역할에 수정 요청이 들어온 사례를 적용한다. 구성 검사 통과와 이 사례 검토, 실제 앱 검증을 별도로 기록한다.

## 구성 검증 기록 · 2026-09-30

- 4개 역할 TOML, 6개 스킬과 UI YAML, 68개 로컬 링크의 구조 검사를 통과했다. 여섯 스킬 모두 skill-creator의 기본 형식 검사도 통과했다.
- 임시 복사본에서 기본 스킬 누락, 연결된 문서 누락, 잘못된 역할 TOML과 잘못된 스킬 YAML을 검사기가 오류로 반환하는 것을 확인했다. 원본 프로젝트 파일은 이 오류 시험으로 변경하지 않았다.
- 로컬 `codex-cli 0.159.0`의 `debug prompt-input`에서 루트 `AGENTS.md`와 여섯 프로젝트 스킬의 발견을 확인했다. 전체 프롬프트 출력은 프로젝트에 저장하지 않았다.
- 독립 검토는 일반 서브에이전트에 `dicom-review` 지침과 검토 배정을 전달해 수행했다. P0 시작, 공유 payload 변경, 독립 기대값 불일치, GPU 환경 부재와 리뷰 역할의 수정 요청 사례를 적용했다.
- 커스텀 TOML 역할의 실제 자동 호출과 동시 실행 상한의 런타임 적용은 별도 미검증이다. 앱 빌드, 실제 DICOM·GPU·저장 시험과 성능 측정은 수행하지 않았다.

## 공식 형식 근거

- [AGENTS.md 프로젝트 지침](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [서브에이전트와 커스텀 역할](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [프로젝트 스킬과 단계적 로딩](https://learn.chatgpt.com/docs/customization/overview#skills)

형식 근거 확인일은 2026-09-30이다. 클라이언트를 바꾸거나 업그레이드할 때는 실제 역할·스킬 발견을 확인한다.
