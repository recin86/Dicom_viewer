---
name: dicom-macos
description: "DICOM Viewer의 Swift macOS 앱 상태·화면·입력과 AppKit/Metal viewport를 구현하고 검증한다. 실제 표시와 원본 좌표, 비동기 요청, GPU 수명과 PNG 출력이 연결된 작업에 사용한다."
---

# macOS 앱과 영상 표시

프로젝트 루트는 `../../..`이다. `AGENTS.md`, `docs/05-ui-and-interaction.md`와 `docs/04-core-api-and-data-model.md`의 해당 계약, `docs/06-development-and-validation.md`의 시험을 읽는다. 플랫폼·GPU 경계에는 `docs/02`와 ADR 0003을 확인한다.

## 앱 상태와 FFI

- Empty/Loading/Ready/Partial/Unsupported/Failed/SourceMissing의 실제 동작을 유지한다. capability와 제한 이유로 도구를 활성화하고 Modality 이름으로 측정 가능 여부를 추정하지 않는다.
- UI 갱신은 MainActor에서 하되 파일 읽기·디코딩·해시는 실제 백그라운드 경로로 실행한다. 선택한 Swift/Xcode 버전의 concurrency와 FFI 실행 경계를 확인한다.
- 요청 선택과 표시 완료 상태를 나누고 generation·source/grouping revision을 검사한다. 새 영상, 라벨과 주석을 함께 교체하고 이전 영상에 새 frame의 측정·번호를 붙이지 않는다.
- 로딩·원본 변경 중 도구 제한, 취소 이후 유지되는 결과, 실패 파일을 건너뛴 탐색과 dirty 표시를 명세에 맞춘다.

## 좌표와 표시

화면 point, backing pixel, 원본 PixelPoint를 구분한다. fit/zoom/pan/회전/반전은 `docs/04`의 변환 순서를 사용하고 영상·방향 문자·주석·hit test·PNG가 같은 변환과 역변환을 공유하게 한다. 픽셀 바깥 경계와 Retina 배율, 비등방 spacing을 포함해 round-trip을 확인한다. 원본 픽셀 조회는 화면 보간값으로 대체하지 않는다.

GrayF32LE는 Modality 변환 후 값을 받으며 DisplayDescriptor의 VOI·극성을 GPU에 적용한다. 이미 정규화한 RGBA8에 회색조 W/L이나 YBR 변환을 다시 적용하지 않는다. valid mask·padding·보간 처리, LUT·MONOCHROME1/DX 극성과 사용자 반전을 CPU 기준 경로와 맞춘다.

텍스처·command buffer 수명과 GPU 완료 후 재활용을 확인한다. W/L·pan·zoom에는 준비된 텍스처를 재사용하고 재디코딩이 필요한 요청과 구분한다. 버퍼 복사 비용과 메모리 사용은 실제로 측정한다.

## 입력·재생·저장

- 1/2/4뷰, 활성 뷰와 텍스트 focus, 마우스/트랙패드, undo 동작을 해당 UI 절에 연결한다. 주석은 화면 좌표가 아닌 원본 좌표로 보존한다.
- cine는 제공된 PlaybackTiming과 trim/loop/sweep 규칙을 사용한다. 실제 표시된 frame과 정지 상태, 누락·중복·지연을 측정한다.
- 파일 선택과 security-scoped 권한의 수명은 Swift가 관리하며 Rust 작업이 끝나기 전에 접근을 해제하지 않는다. 선택한 배포 방식에 필요하지 않은 bookmark나 Sandbox를 이미 채택했다고 가정하지 않는다.
- PNG는 실제 표시 파이프라인과 좌표 변환을 공유한다. 오버레이 선택을 반영하고 출력 파일을 다시 확인한다. 환자 정보 숨김이 원문 태그·경로·메모·burned-in 문자까지 제거한다고 설명하지 않는다.

## 검증과 반환

T-04~T-06/T-08/T-11~T-13/T-16~T-18/T-21 중 배정 범위를 실제 macOS에서 확인한다. Metal 수치는 색공간·보간을 고정한 offscreen 기준 출력과 비교하고 화면 사용성은 실제 창에서 확인한다.

scheme·target·의존성 파일은 실제 프로젝트에서 확인하고 변경 작성권은 메인과 맞춘다. GPU 제출과 실제 presentation을 구분하고 성능 환경·표본 수를 보고한다. 실제 Mac/GPU 시험을 실행하지 않았다면 not-run이다.

변경 파일, 필요한 FFI·빌드 변경, 실행 환경·결과와 남은 UI/수치 검증 범위를 메인에게 반환한다.
