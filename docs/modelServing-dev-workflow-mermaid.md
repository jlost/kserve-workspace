# Model Serving Development Workflow – Summary and Mermaid Diagrams

Summary and Mermaid versions of the drawio workflows for KServe/ModelMesh and odh-model-controller.

---

## Summary

The drawio file describes **two decision workflows** for getting changes into RHOAI (Red Hat OpenShift AI) model serving:

### 1. KServe / ModelMesh workflow

- **Entry:** “Is this a new feature?”
  - **Yes:** “Can you contribute to upstream (kserve/kserve)?”
    - **Yes:** Work on **Upstream/kserve master**; when upstream PR is merged, either wait for Monday sync to ODH or (if it must be in this RHOAI release) follow the RHOAI release path (code freezes, cherry-picks, syncs).
    - **No:** Work on **ODH/kserve master**; then “Need to be in this RHOAI release?” drives the same release path.
  - **No (not a new feature):** “Is it a CVE?”
    - **Yes:** Follow **CVE process** (red.ht/modelserving-cve-process).
    - **No:** Same “Can contribute to upstream?” branch as above.
- **RHOAI release path:** “Need to be in this RHOAI release?” → “Does it pass Internal Code Freeze?” → “Does it pass Official Code Freeze?”. If it fails a freeze: report to team, get approval (with Jira for KServe/ModelMesh), then either cherry-pick to odh/release and sync odh/master → odh/release, or wait for the **regular sync process**.
- **Regular sync (ODH Release Process Owner):** Every Monday sync upstream → odh master; first/second/last week of sprint: “Start ODH Release Process” (red.ht/odh-model-process). **Process:** release odh-model-controller, KServe, ModelMesh (GitHub actions), update image tags on quay.io, then **post process:** sync odh/release → rhoai/main (odh-model-controller) or rhoai/master (KServe, ModelMesh).

### 2. odh-model-controller workflow

- **Entry:** “Is this a new feature?”
  - **Yes:** “Can contribute to upstream?” → **Work with ODH/odh-model-controller incubating branch**.
  - **No:** “Is it a CVE?”
    - **Yes:** Follow **CVE process** (red.ht/modelserving-cve-process).
    - **No:** Same → **Work with ODH/odh-model-controller incubating branch**.
- **RHOAI release:** “Need to be in this RHOAI release?” → “Does it pass Internal Code Freeze?” → “Does it pass Official Code Freeze?”. If it fails: report to team and get **verbal** approval, then either “Wait for regular sync” or manual path: **Sync from odh/incubating to RHOAI/release** (Cherry-pick to odh/main from incubating → Sync odh/main → RHOAI/main → Sync RHOAI/main → RHOAI/release). All manual except where noted.
- **Regular sync and post process** match the KServe/ModelMesh diagram (ODH release process, release repos, update quay.io tags, sync odh/release to rhoai/main or rhoai/master).

---

## Mermaid: KServe / ModelMesh workflow

```mermaid
flowchart TD
    Start([Start])
    Start --> Q1{Is a new feature?}

    Q1 -->|Y| Q2{Can contribute to upstream?}
    Q1 -->|N| Q3{Is CVE?}

    Q2 -->|Y| A1[Work with Upstream/kserve master]
    Q2 -->|N| A2[Work with ODH/kserve master]

    Q3 -->|Y| CVE[Follow CVE Process<br>red.ht/modelserving-cve-process]
    Q3 -->|N| Q2

    A1 --> Q4{Upstream PR merged?}
    Q4 -->|Y| Q5{Need to be in this RHOAI release?}
    Q4 -->|N| Q6{Can wait for merging?}

    Q6 -->|Y| Wait1[Wait for upstream merge.<br>Changes sync upstream to odh/master next Monday.]
    Q6 -->|N| ODHFirst[Send PR to ODH/master first.<br>Contribute to upstream in parallel.]
    ODHFirst --> Q5

    Wait1 --> SyncPath[Sync upstream/master to odh/master - Every Monday by ODH release owner]
    SyncPath --> CP1[Cherry-pick your PR to odh/release - PR Author]
    CP1 --> Sync2[Sync odh/release to RHOAI/master - Last week of sprint by ODH release owner]
    Sync2 --> WaitReg[Wait for regular sync process]

    Q5 -->|Y| Q7{Does it pass Internal Code Freeze?}
    Q5 -->|N| CherryWait[Cherry-pick the PR to odh/release.<br>Wait for regular sync process.]

    Q7 -->|Y| Q8{Does it pass Official Code Freeze?}
    Q7 -->|N| ManualPath[Merge the commit to odh/master.<br>Cherry-pick your PR to odh/release.<br>Sync from odh/master to odh/release.<br>Wait for regular sync process.]

    Q8 -->|Y| Report[Report to team and get approval with Jira ticket]
    Q8 -->|N| ManualPath
    Report --> SyncFromOdh[Sync from odh/master to odh/release]
    SyncFromOdh --> CP2[Cherry-pick your PR to odh/release]
    CP2 --> Sync3[Sync from odh/release to RHOAI/master]
    Sync3 --> Sync4[Sync from RHOAI/master to RHOAI/release]

    CherryWait --> RegularSync[Regular Sync Process]

    subgraph RegularSync["Regular Sync Process (ODH Release Process Owner)"]
        Mon[Every Monday: Sync upstream to odh master]
        Sprint[First / Second / Last week of sprint]
        StartODH[Start ODH Release Process<br>red.ht/odh-model-process]
    end

    subgraph Process["Process"]
        OMC[odh-model-controller]
        KS[KServe]
        MM[ModelMesh]
        OMC --> Release1[Execute gitaction to release odh version]
        KS --> Release2[Execute gitaction to release odh version]
        MM --> Release3[Execute gitaction to release odh version]
        Release1 --> UpdateImg[Update Image Tag on quay.io]
        Release2 --> UpdateImg
        Release3 --> UpdateImg
    end

    subgraph PostProcess["Post Process"]
        UpdateImg --> SyncMain[Sync odh/release to rhoai/main - odh-model-controller]
        UpdateImg --> SyncMaster1[Sync odh/release to rhoai/master - KServe]
        UpdateImg --> SyncMaster2[Sync odh/release to rhoai/master - ModelMesh]
    end
```

---

## Mermaid: odh-model-controller workflow

```mermaid
flowchart TD
    Start([Start])
    Start --> Q1{Is a new feature?}

    Q1 -->|Y| Q2{Can contribute to upstream?}
    Q1 -->|N| Q3{Is CVE?}

    Q2 -->|Y| A1[Work with ODH/odh-model-controller incubating branch]
    Q2 -->|N| A1

    Q3 -->|Y| CVE[Follow CVE Process<br>red.ht/modelserving-cve-process]
    Q3 -->|N| A1

    A1 --> Q4{Need to be in this RHOAI release?}
    Q4 -->|Y| Q5{Does it pass Internal Code Freeze?}
    Q4 -->|N| WaitSync[Wait for regular sync process]

    Q5 -->|Y| Q6{Does it pass Official Code Freeze?}
    Q5 -->|N| WaitSync

    Q6 -->|Y| Report[Report to team and get verbal approval]
    Q6 -->|N| WaitSync
    Report --> ManualPath[Sync from odh/incubating to RHOAI/release]

    subgraph ManualPathDetail["Manual path (all manual)"]
        CP1[Cherry-pick your PR to odh/main from odh/incubating]
        CP1 --> S1[Sync from odh/main to RHOAI/main]
        S1 --> S2[Sync from RHOAI/main to RHOAI/release]
    end

    WaitSync --> RegularSync[Regular Sync Process]

    subgraph RegularSync["Regular Sync Process (ODH Release Process Owner)"]
        Mon[Every Monday: Sync upstream to odh master]
        Sprint[First / Second / Last week of sprint]
        StartODH[Start ODH Release Process<br>red.ht/odh-model-process]
    end

    subgraph Process["Process"]
        OMC[odh-model-controller]
        KS[KServe]
        MM[ModelMesh]
        OMC --> Release1[Execute gitaction to release odh version]
        KS --> Release2[Execute gitaction to release odh version]
        MM --> Release3[Execute gitaction to release odh version]
        Release1 --> UpdateImg[Update Image Tag on quay.io]
        Release2 --> UpdateImg
        Release3 --> UpdateImg
    end

    subgraph PostProcess["Post Process"]
        UpdateImg --> SyncMain[Sync odh/release to rhoai/main - odh-model-controller]
        UpdateImg --> SyncMaster1[Sync odh/release to rhoai/master - KServe]
        UpdateImg --> SyncMaster2[Sync odh/release to rhoai/master - ModelMesh]
    end
```

---

## References (from drawio)

- CVE process: red.ht/modelserving-cve-process  
- ODH release process: red.ht/odh-model-process  
