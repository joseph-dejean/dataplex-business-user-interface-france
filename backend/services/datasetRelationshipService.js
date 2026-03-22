const { Firestore } = require('@google-cloud/firestore');
const { CatalogServiceClient, protos } = require('@google-cloud/dataplex');
const { GoogleAuth } = require('google-auth-library');
const { BigQuery } = require('@google-cloud/bigquery');

let bigqueryClient = null;
const getBigQueryClient = () => {
    if (!bigqueryClient) {
        bigqueryClient = new BigQuery();
    }
    return bigqueryClient;
};

let firestore = null;
const getFirestore = () => {
    if (!firestore) {
        const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT_ID;
        firestore = new Firestore(projectId ? { projectId } : {});
        console.log('Firestore initialized for dataset relationships, project:', projectId || 'auto-detect');
    }
    return firestore;
};

const COLLECTION_NAME = 'dataset-relationships';
const CACHE_TTL_HOURS = 24;

let catalogClient = null;
const getCatalogClient = () => {
    if (!catalogClient) {
        catalogClient = new CatalogServiceClient();
    }
    return catalogClient;
};

let authClient = null;
const getAuthClient = async () => {
    if (!authClient) {
        const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
        authClient = await auth.getClient();
    }
    return authClient;
};

const parseFqn = (fqn) => {
    const clean = fqn.replace('bigquery:', '').replace('bigquery://', '');
    const parts = clean.split('.');
    if (parts.length >= 3) {
        return { project: parts[0], dataset: parts[1], table: parts[2] };
    }
    return null;
};

/**
 * Trigger DataScan with dataDocumentationSpec via REST API.
 */
const triggerDocumentationScan = async (billingProject, location, bqProject, bqDataset, bqTable) => {
    try {
        const client = await getAuthClient();
        const baseScanId = `doc-scan-${bqProject}-${bqDataset}-${bqTable}`.replace(/[^a-z0-9-]/gi, '-').toLowerCase();
        // ensure valid id
        const dataScanId = baseScanId.length > 63 ? baseScanId.substring(0, 63) : baseScanId;

        const url = `https://dataplex.googleapis.com/v1/projects/${billingProject}/locations/${location}/dataScans?dataScanId=${dataScanId}`;
        console.log(`[RELATIONSHIPS] Triggering DataScan (Discovery Phase) for ${bqProject}.${bqDataset}.${bqTable}: ${dataScanId}`);

        await client.request({
            url,
            method: 'POST',
            data: {
                data: {
                    resource: `//bigquery.googleapis.com/projects/${bqProject}/datasets/${bqDataset}/tables/${bqTable}`
                },
                dataDocumentationSpec: {},
                executionSpec: {
                    trigger: { onDemand: {} }
                }
            }
        });

        console.log(`[RELATIONSHIPS] DataScan created successfully for ${bqTable}`);
        // Scan created — now trigger the first run
        try {
            const runUrl = `https://dataplex.googleapis.com/v1/projects/${billingProject}/locations/${location}/dataScans/${dataScanId}:run`;
            await client.request({ url: runUrl, method: 'POST', data: {} });
            console.log(`[RELATIONSHIPS] DataScan run triggered for ${bqTable}`);
        } catch (runErr) {
            console.warn(`[RELATIONSHIPS] DataScan run trigger failed for ${bqTable}:`, runErr.message);
        }
    } catch (err) {
        if (err.response && err.response.status === 409) {
            console.log(`[RELATIONSHIPS] DataScan ALREADY EXISTS for ${bqTable}. Triggering a run...`);
            // Actually run the existing scan so documentation aspects get populated
            try {
                const client2 = await getAuthClient();
                const baseScanId2 = `doc-scan-${bqProject}-${bqDataset}-${bqTable}`.replace(/[^a-z0-9-]/gi, '-').toLowerCase();
                const dataScanId2 = baseScanId2.length > 63 ? baseScanId2.substring(0, 63) : baseScanId2;
                const runUrl = `https://dataplex.googleapis.com/v1/projects/${billingProject}/locations/${location}/dataScans/${dataScanId2}:run`;
                await client2.request({ url: runUrl, method: 'POST', data: {} });
                console.log(`[RELATIONSHIPS] DataScan run triggered for existing scan: ${bqTable}`);
            } catch (runErr) {
                // 409 on run means a run is already in progress — that's fine
                if (runErr.response && runErr.response.status === 409) {
                    console.log(`[RELATIONSHIPS] DataScan run already in progress for ${bqTable}`);
                } else {
                    console.warn(`[RELATIONSHIPS] Failed to trigger run for existing scan ${bqTable}:`, runErr.message);
                }
            }
        } else {
            console.warn(`[RELATIONSHIPS] Error creating DataScan for ${bqTable}:`, err.response ? JSON.stringify(err.response.data) : err.message);
        }
    }
};

/**
 * Implement a recursive lookup reading the Documentation Aspect from Dataplex Catalog.
 * up to maxDegree 3.
 */
/**
 * Try to fetch a Dataplex entry by looking up its FQN via searchEntries.
 * This avoids needing to know the exact entry name/location format.
 */
const lookupEntryByFqn = async (client, billingProject, fqn) => {
    // Step 1: Use searchEntries to discover the entry's actual name and location
    const searchQuery = `fully_qualified_name=${fqn}`;
    try {
        const [response] = await client.searchEntries({
            name: `projects/${billingProject}/locations/global`,
            query: searchQuery,
            pageSize: 1,
        });
        const results = response.results || response;
        if (results && results.length > 0) {
            const searchResult = results[0].dataplexEntry || results[0];
            const entryName = searchResult.name;
            if (entryName) {
                // Step 2: Fetch the FULL entry with aspects using the discovered name
                console.log(`[RELATIONSHIPS] Found entry via search, fetching full entry: ${entryName}`);
                try {
                    const [fullEntry] = await client.getEntry({
                        name: entryName,
                        view: protos.google.cloud.dataplex.v1.EntryView.ALL
                    });
                    if (fullEntry) return fullEntry;
                } catch (getErr) {
                    console.warn(`[RELATIONSHIPS] getEntry failed for ${entryName}:`, getErr.message);
                    // Fall through to location-based fallback
                }
            }
        }
    } catch (err) {
        console.warn(`[RELATIONSHIPS] searchEntries failed for ${fqn}:`, err.message);
    }

    // Fallback: try getEntry with multiple location formats
    const parsed = parseFqn(fqn);
    if (!parsed) return null;

    const locations = ['global', 'us', 'eu', 'europe-west1', 'us-central1'];
    for (const loc of locations) {
        try {
            const entryName = `projects/${parsed.project}/locations/${loc}/entryGroups/@bigquery/entries/bigquery.googleapis.com/projects/${parsed.project}/datasets/${parsed.dataset}/tables/${parsed.table}`;
            const [entry] = await client.getEntry({
                name: entryName,
                view: protos.google.cloud.dataplex.v1.EntryView.ALL
            });
            if (entry) return entry;
        } catch (_) {
            // Try next location
        }
    }
    return null;
};

/**
 * Infer relationships from BigQuery schema by analyzing column naming patterns.
 * Looks for columns like table_id, table_name, tableId that match other table names.
 */
const inferRelationshipsFromSchema = async (bqProject, bqDataset, tableNames) => {
    const relationships = [];
    try {
        const bq = getBigQueryClient();
        const query = `
            SELECT table_name, column_name
            FROM \`${bqProject}.${bqDataset}.INFORMATION_SCHEMA.COLUMNS\`
            WHERE table_name IN UNNEST(@tableNames)
            ORDER BY table_name, ordinal_position
        `;
        // Try without explicit location first (auto-detect), then fall back to common locations
        let rows;
        const locations = [undefined, 'EU', 'US', 'europe-west1', 'us-central1'];
        for (const loc of locations) {
            try {
                const opts = { query, params: { tableNames } };
                if (loc) opts.location = loc;
                const [result] = await bq.query(opts);
                rows = result;
                console.log(`[RELATIONSHIPS] BQ INFORMATION_SCHEMA query succeeded${loc ? ` (location: ${loc})` : ' (auto-detect)'}`);
                break;
            } catch (locErr) {
                if (loc === locations[locations.length - 1]) throw locErr;
                // Try next location
            }
        }
        if (!rows) rows = [];

        // Build a map of table -> columns
        const tableColumns = {};
        for (const row of rows) {
            if (!tableColumns[row.table_name]) tableColumns[row.table_name] = [];
            tableColumns[row.table_name].push(row.column_name.toLowerCase());
        }

        // Log columns for debugging
        for (const [tbl, cols] of Object.entries(tableColumns)) {
            console.log(`[RELATIONSHIPS] Table "${tbl}" columns: ${cols.join(', ')}`);
        }

        const tableNamesLower = tableNames.map(t => t.toLowerCase());
        const seen = new Set();

        for (const [tableName, columns] of Object.entries(tableColumns)) {
            for (const col of columns) {
                // Match patterns: other_table_id, other_table_key, other_tableId, fk_other_table
                for (const otherTable of tableNamesLower) {
                    if (otherTable === tableName.toLowerCase()) continue;

                    const patterns = [
                        `${otherTable}_id`,
                        `${otherTable}_key`,
                        `${otherTable}id`,
                        `fk_${otherTable}`,
                        `${otherTable}_fk`,
                        `id_${otherTable}`,
                    ];
                    // Also handle singular forms: if table is "departments", check "department_id"
                    const singular = otherTable.endsWith('s') ? otherTable.slice(0, -1) : otherTable;
                    if (singular !== otherTable) {
                        patterns.push(`${singular}_id`, `${singular}_key`, `${singular}id`, `id_${singular}`);
                    }
                    // Handle underscored table names: "job_history" -> check "job_history_id"
                    // Also check partial matches: column contains the table name
                    // e.g., column "dept_id" for table "department" won't match exact patterns,
                    // but column "employee_id" for table "employee" will

                    if (patterns.includes(col)) {
                        const edgeKey = [tableName, otherTable].sort().join('|');
                        if (!seen.has(edgeKey)) {
                            seen.add(edgeKey);
                            const actualOther = tableNames.find(t => t.toLowerCase() === otherTable) || otherTable;
                            relationships.push({
                                table1: tableName,
                                table2: actualOther,
                                relationship: `Inferred from column: ${tableName}.${col}`,
                                confidence: 'medium (schema)',
                                source: 'Schema Column Analysis'
                            });
                        }
                    }
                }

                // Also check: any column ending with _id where the prefix matches any table name
                // e.g., "dept_id" -> check if any table starts with "dept" (abbreviation matching)
                if (col.endsWith('_id') || col.endsWith('_key')) {
                    const prefix = col.replace(/_id$/, '').replace(/_key$/, '');
                    for (const otherTable of tableNamesLower) {
                        if (otherTable === tableName.toLowerCase()) continue;
                        // Check if table name starts with the prefix or prefix starts with table name
                        // e.g., "dept" matches "department", "emp" matches "employee"
                        if (otherTable.startsWith(prefix) || prefix.startsWith(otherTable.substring(0, 3))) {
                            const edgeKey = [tableName, otherTable].sort().join('|');
                            if (!seen.has(edgeKey)) {
                                seen.add(edgeKey);
                                const actualOther = tableNames.find(t => t.toLowerCase() === otherTable) || otherTable;
                                relationships.push({
                                    table1: tableName,
                                    table2: actualOther,
                                    relationship: `Inferred from column: ${tableName}.${col}`,
                                    confidence: 'low (pattern)',
                                    source: 'Schema Column Analysis'
                                });
                            }
                        }
                    }
                }
            }
        }

        console.log(`[RELATIONSHIPS] Schema inference found ${relationships.length} relationships for ${bqProject}.${bqDataset}`);
    } catch (err) {
        console.warn(`[RELATIONSHIPS] Schema inference failed for ${bqProject}.${bqDataset}:`, err.message);
    }
    return relationships;
};

const fetchRelationshipsFromCatalog = async (billingProject, location, rootTablesFqns, maxDegree = 3) => {
    const relationships = [];
    const visited = new Set();
    const queue = [];
    let scansTriggered = 0;

    for (const fqn of rootTablesFqns) {
        const parsed = parseFqn(fqn);
        if (parsed) {
            queue.push({ ...parsed, fqn: fqn.replace('bigquery:', '').replace('bigquery://', ''), degree: 0 });
            visited.add(`${parsed.project}.${parsed.dataset}.${parsed.table}`);
        }
    }

    const client = getCatalogClient();

    while (queue.length > 0) {
        const current = queue.shift();

        if (current.degree > maxDegree) continue;

        const currentFqn = `bigquery:${current.project}.${current.dataset}.${current.table}`;
        console.log(`[RELATIONSHIPS] Fetching aspects for ${current.project}.${current.dataset}.${current.table} at degree ${current.degree}`);

        try {
            const entry = await lookupEntryByFqn(client, billingProject, currentFqn);

            if (!entry || !entry.aspects) {
                console.log(`[RELATIONSHIPS] No entry/aspects for ${current.table}, triggering DataScan...`);
                await triggerDocumentationScan(billingProject, location, current.project, current.dataset, current.table);
                scansTriggered++;
                continue;
            }

            const aspectKeys = Object.keys(entry.aspects);
            const docAspectKey = aspectKeys.find(k => k.includes('data_documentation') || k.includes('documentation'));

            if (docAspectKey && entry.aspects[docAspectKey]) {
                const docData = entry.aspects[docAspectKey].data;
                const fields = docData && docData.fields ? docData.fields : {};

                let relatedEntities = null;
                if (fields.related_entities && fields.related_entities.listValue) {
                    relatedEntities = fields.related_entities.listValue.values;
                } else if (fields.relatedEntities && fields.relatedEntities.listValue) {
                    relatedEntities = fields.relatedEntities.listValue.values;
                } else {
                    for (const key of Object.keys(fields)) {
                        if (key.toLowerCase().includes('related') && fields[key].listValue) {
                            relatedEntities = fields[key].listValue.values;
                            break;
                        }
                    }
                }

                if (relatedEntities && relatedEntities.length > 0) {
                    for (const ent of relatedEntities) {
                        const entFields = ent.structValue && ent.structValue.fields ? ent.structValue.fields : {};
                        const relatedTableFqn = (entFields.table && entFields.table.stringValue) || (entFields.entity && entFields.entity.stringValue) || (entFields.name && entFields.name.stringValue);
                        const relationshipDescription = (entFields.relationship && entFields.relationship.stringValue) || 'AI-Inferred Relationship';

                        if (relatedTableFqn) {
                            const parsedRel = parseFqn(relatedTableFqn);
                            if (parsedRel) {
                                relationships.push({
                                    table1: current.table,
                                    table2: parsedRel.table,
                                    relationship: relationshipDescription,
                                    confidence: 'high (AI)',
                                    source: 'Dataplex Catalog DataDocumentation'
                                });

                                const relKey = `${parsedRel.project}.${parsedRel.dataset}.${parsedRel.table}`;
                                if (!visited.has(relKey) && current.degree < maxDegree) {
                                    visited.add(relKey);
                                    queue.push({ ...parsedRel, degree: current.degree + 1 });
                                }
                            }
                        }
                    }
                }
            } else {
                console.log(`[RELATIONSHIPS] No documentation aspect for ${current.table}, triggering DataScan...`);
                await triggerDocumentationScan(billingProject, location, current.project, current.dataset, current.table);
                scansTriggered++;
            }

        } catch (err) {
            if (err.code === 5 || (err.message && err.message.includes('NOT_FOUND'))) {
                await triggerDocumentationScan(billingProject, location, current.project, current.dataset, current.table);
                scansTriggered++;
            } else {
                console.warn(`[RELATIONSHIPS] Entry fetch error for ${current.table}:`, err.message);
            }
        }
    }

    // If scans were triggered and we have no relationships, try schema-based inference as fallback
    if (relationships.length === 0 && rootTablesFqns.length > 0) {
        const parsed = parseFqn(rootTablesFqns[0]);
        if (parsed) {
            const tableNames = rootTablesFqns.map(fqn => {
                const p = parseFqn(fqn);
                return p ? p.table : null;
            }).filter(Boolean);

            console.log(`[RELATIONSHIPS] No catalog relationships found. Trying schema-based inference for ${tableNames.length} tables...`);
            const schemaRels = await inferRelationshipsFromSchema(parsed.project, parsed.dataset, tableNames);
            relationships.push(...schemaRels);
        }
    }

    return { relationships, scansTriggered };
};

/**
 * Get cached relationships from Firestore
 */
const getCachedRelationships = async (projectId, datasetId) => {
    try {
        const db = getFirestore();
        const cacheKey = `${projectId}.${datasetId}`;
        const docRef = db.collection(COLLECTION_NAME).doc(cacheKey);
        const doc = await docRef.get();

        if (!doc.exists) return null;

        const data = doc.data();
        const cachedAt = data.cachedAt?.toDate ? data.cachedAt.toDate() : new Date(data.cachedAt);
        const now = new Date();
        const hoursSinceCached = (now - cachedAt) / (1000 * 60 * 60);

        if (hoursSinceCached > CACHE_TTL_HOURS) {
            console.log(`[RELATIONSHIPS] Cache expired for ${cacheKey} (${hoursSinceCached.toFixed(1)}h old)`);
            return null;
        }

        console.log(`[RELATIONSHIPS] Cache hit for ${cacheKey} (${hoursSinceCached.toFixed(1)}h old)`);
        return data.relationships;
    } catch (error) {
        console.warn('[RELATIONSHIPS] Cache read error:', error.message);
        return null;
    }
};

/**
 * Store relationships in Firestore cache
 */
const cacheRelationships = async (projectId, datasetId, relationships, tablesCount) => {
    try {
        const db = getFirestore();
        const cacheKey = `${projectId}.${datasetId}`;
        const docRef = db.collection(COLLECTION_NAME).doc(cacheKey);

        await docRef.set({
            projectId,
            datasetId,
            relationships,
            tableCount: tablesCount,
            cachedAt: new Date().toISOString(),
            inferredAt: new Date().toISOString()
        });

        console.log(`[RELATIONSHIPS] Cached ${relationships.length} relationships for ${cacheKey}`);
    } catch (error) {
        console.warn('[RELATIONSHIPS] Cache write error:', error.message);
    }
};

/**
 * Invalidate cache for a dataset (call when schema changes)
 */
const invalidateCache = async (projectId, datasetId) => {
    try {
        const db = getFirestore();
        const cacheKey = `${projectId}.${datasetId}`;
        await db.collection(COLLECTION_NAME).doc(cacheKey).delete();
        console.log(`[RELATIONSHIPS] Cache invalidated for ${cacheKey}`);
    } catch (error) {
        console.warn('[RELATIONSHIPS] Cache invalidate error:', error.message);
    }
};

/**
 * Add a manual relationship (user-defined)
 */
const addManualRelationship = async (projectId, datasetId, relationship) => {
    try {
        const db = getFirestore();
        const cacheKey = `${projectId}.${datasetId}`;
        const docRef = db.collection(COLLECTION_NAME).doc(cacheKey);
        const doc = await docRef.get();

        let relationships = [];
        if (doc.exists) relationships = doc.data().relationships || [];

        relationships.push({
            ...relationship,
            confidence: 'manual',
            addedAt: new Date().toISOString()
        });

        await docRef.set({
            projectId,
            datasetId,
            relationships,
            cachedAt: new Date().toISOString()
        }, { merge: true });

        return relationships;
    } catch (error) {
        console.error('[RELATIONSHIPS] Add manual relationship error:', error.message);
        throw error;
    }
};

module.exports = {
    fetchRelationshipsFromCatalog,
    inferRelationshipsFromSchema,
    getCachedRelationships,
    cacheRelationships,
    invalidateCache,
    addManualRelationship,
    CACHE_TTL_HOURS
};
