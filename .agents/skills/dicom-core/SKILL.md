---
name: dicom-core
description: "DICOM Viewer의 Rust/dicom-rs 코어에서 DICOM 해석·디코딩, 프레임·공간·시간 모델, 계산·캐시와 연구 프로젝트 저장을 구현하거나 조사한다. Swift 화면과 FFI 공개 계약의 독립 변경에는 사용하지 않는다."
---

# DICOM Rust 코어 구현

프로젝트 루트는 `../../..`이다. `AGENTS.md`와 배정을 확인하고 `docs/03-dicom-support.md`, `docs/04-core-api-and-data-model.md` 및 `docs/06-development-and-validation.md`에서 작업 관련 절을 읽는다. 코어 책임·요청 큐 변경에는 `docs/02`, 저장 결정에는 ADR 0004를 추가로 읽는다.

## DICOM 입력과 픽셀

- 지원 판정은 SOP Class, Transfer Syntax, 픽셀 표현, 필요한 변환과 포함된 decoder 조합으로 한다. 라이브러리 등록과 실제 decoder 사용 가능, 파일 파싱과 정확한 표시를 구분한다.
- 채택한 dicom-rs 버전과 feature의 공식 자료 및 실제 호출 옵션을 확인한다. 특히 디코딩 함수의 출력 단계가 저장 값인지 Modality/VOI 적용 값인지 확인하고 rescale·LUT·컬러 변환을 한 번만 적용한다.
- signedness·유효 비트·endian·planar layout·padding·Photometric Interpretation을 해석하고, 압축 frame 경계·fragment·offset table을 검증한다. 필요한 변환을 무시한 그럴듯한 영상을 성공으로 반환하지 않는다.
- 합성 golden과 채택 코덱의 독립 기준 디코딩 결과를 사용한다. 실제 자료와 필요한 codec가 없으면 지원 상태를 검증됨으로 올리지 않는다.

## 공간·시간·계산

- 파일, instance, frame과 display set을 구분한다. SpatialStack/TemporalSequence/UnorderedFrames를 유지하고 서로 다른 echo·시간·Frame of Reference를 단일 볼륨으로 몰아넣지 않는다.
- 정렬과 geometry는 `docs/03`의 근거를 따른다. 정보가 없거나 충돌하면 optional과 diagnostics를 유지하고 capability를 제한한다.
- row/column spacing, 열 x/행 y, LPS와 0/1기반 frame 변환을 명시한다. 표시 종횡비·Pixel Aspect Ratio·검출기 간격을 환자 공간 보정으로 승격하지 않는다.
- 측정은 원본 좌표와 F64 경로에서 수행한다. ROI 중심 포함, padding 제외, 유효 count와 모집단 SD·sampled area·빈 결과 의미는 `docs/04`를 따른다.
- cine의 기록 획득 시각과 추정 재생 시각을 구분하고 trim 이후 원본 frame number를 보존한다.

## 엔진과 자원

source/grouping revision을 캐시·요청에 반영한다. 대기·진행 중·반환 버퍼와 codec 내부 메모리를 구분해 바이트 한도를 관리하고 할당 전 크기 곱을 검사한다. terminal 상태·취소·세션 close의 계약을 지킨다. 무거운 동기 작업을 UI thread에 실행하는 API 경로를 만들지 않는다.

## 연구 프로젝트 저장 작업

P3/P4 배정에만 아래 절을 적용한다.

- 인덱스와 사용자 연구 작업의 유일한 저장소를 분리한다. 제안된 저장 형식을 채택할 때는 OQ-07과 ADR 0004의 근거를 확인한다.
- 주석·메모·뷰 상태의 영속 참조에 content hash와 원본 frame number를 포함한다. UID/경로/세션 ID만 같은 파일에 자동 적용하지 않는다. 해시와 픽셀의 source revision을 일치시킨다.
- snapshot 저장, file token 사전조건, 충돌 검사, 마지막 유효 문서, 저장 중 편집의 dirty 상태와 migration 원본 사본을 검증한다. 알 수 없는 미래 schema를 덮어쓰지 않는다.
- CSV는 실제 값·단위·보정·stale 상태를 보존하고 quoting과 자유 텍스트 수식 해석 방지를 별도로 다룬다. PNG는 앱 renderer의 책임이다.

## 검증과 반환

관련 T-01~T-15/T-17~T-19/T-21 사례를 선택해 정상·실패·경계 결과를 확인한다. 존재하는 Cargo manifest와 명령을 사용하고 공통 의존성 변경이 필요하면 메인에게 전달한다. fixture 작성자와 같은 파일을 동시에 수정하지 않는다.

변경 파일, decoder 단계·수치 근거, 계약 영향, 실제 실행 결과, not-run과 필요한 환경을 반환한다. 전체 문서를 반복하거나 파일 한 개의 성공을 modality 전체의 지원으로 보고하지 않는다.
