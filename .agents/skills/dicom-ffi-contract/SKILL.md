---
name: dicom-ffi-contract
description: "DICOM Viewer의 Rust–Swift API, 공개 타입, 픽셀 버퍼, 요청·취소·세션 수명과 영속 프레임 참조 계약을 검증하고 변경을 조정한다. FFI 경계나 양쪽 모듈에 영향을 주는 데이터 계약 변경에 사용한다."
---

# Rust–Swift 계약 관리

프로젝트 루트는 `../../..`이다. `AGENTS.md`, `docs/02-system-architecture.md`, `docs/04-core-api-and-data-model.md`의 관련 절과 `docs/06-development-and-validation.md`의 해당 T 항목을 읽는다. P0 연결 방식 선택에는 ADR 0002도 읽는다.

## 변경 전 확인

- 계약의 producer, consumer, generator와 관련 시험을 찾는다. 공개 필드뿐 아니라 단위·변환 단계·optional 의미·오류·thread·소유권·revision을 확인한다.
- 개념 API를 컴파일 가능한 선언으로 옮길 때 채택한 UniFFI runtime/generator 버전에서 표현 가능한 타입과 async/error 경로를 직접 확인한다.
- P0 실험은 사용한 OS/CPU, Swift/Xcode, Rust, 연결 방식, 버퍼 크기와 복사 비용을 기록한다. 타입 몇 개의 생성 성공을 전체 API 검증으로 확대하지 않는다.

## 픽셀과 표시 계약

현재 작업안의 `FramePayload`, `DisplayDescriptor`, `FrameRef` 정의는 `docs/04`를 기준으로 한다. 회색조 GrayF32LE는 Modality 변환 후·VOI 전이고 컬러 RGBA8은 Rust에서 정규화된 표시 컬러다. Swift가 rescale·색변환을 다시 적용하지 않도록 producer의 실제 함수/옵션과 consumer의 texture/shader 경로를 함께 확인한다.

크기·stride·bytes·mask 길이·endian과 overflow를 할당·업로드 전에 확인한다. valid mask, non-finite 값과 F32 overflow의 의미를 소비자까지 유지한다. 표시용 F32 버퍼와 측정용 원본/F64 경로를 구분한다. 다른 픽셀 형식을 도입하면 관련 문서와 CPU/GPU 기준 시험을 함께 갱신한다.

## 요청·수명·오류

- `request_id`, viewport generation, FrameRef/source revision과 grouping revision의 생성·검사 위치를 확인한다. 늦은 결과가 최신 영상·라벨·주석을 덮지 않게 한다.
- cancel은 best-effort 작업 중단이다. terminal 결과는 한 번만 확정되고, close 이후 새 요청과 이미 반환된 immutable payload의 수명은 구분된다.
- Swift UI는 MainActor에 있고 무거운 FFI는 실제 백그라운드 실행 경로를 갖는다. Task 생성만으로 이동했다고 판정하지 않는다.
- 반환 payload는 cache eviction·세션 close 후에도 유효해야 한다. 포인터 공유 도입은 병목 증거, retain/release·thread·allocator·GPU 완료 규칙을 새로운 ADR과 시험으로 다룬다.
- 오류는 구조화된 의미로 전달하고 일반 원문 경로·환자 태그를 포함하지 않는다. panic/unwind와 네이티브 codec crash의 경계를 구분한다.

## 영속 참조와 저장

세션 ID와 프로젝트 영속 참조를 구분한다. content hash·DICOM frame number·source 연결, snapshot revision과 저장 파일 token, 저장 receipt와 현재 dirty 상태를 producer/consumer 모두에서 확인한다. API index는 0기반, 영속 DICOM frame number는 1기반이다.

## 변경과 완료 증거

메인은 공유 계약 변경을 관련 작성자에게 전달하고 생성 입력·버전·문서·양쪽 소비자와 시험을 맞춘다. 생성 바인딩의 수정을 통해 불일치를 숨기지 않는다.

T-04~T-06/T-21의 변환·좌표, T-11~T-13의 버퍼·요청·한도, T-14~T-15의 저장·재연결 중 변경에 해당하는 시험을 선택한다. 실제 양쪽 바인딩을 통과한 결과와 사용한 revision을 기록하고 연결 미실행은 not-run으로 보고한다.
