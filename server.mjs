import express from 'express';
import fs from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';
import { exec } from 'child_process';
import util from 'util';

const execAsync = util.promisify(exec);

const CONFIG_FILE = process.env.CONFIG_FILE || '/projects.json';
let projectsConfig = [];

if (existsSync(CONFIG_FILE)) {
    const data = await fs.readFile(CONFIG_FILE, 'utf-8');
    projectsConfig = JSON.parse(data);
} else if (process.env.REPO_URL) {
    projectsConfig.push({
        REPO_URL: process.env.REPO_URL,
        GIT_TOKEN: process.env.GIT_TOKEN || '',
        BRANCH_REGEX: process.env.BRANCH_REGEX || ''
    });
}

if (projectsConfig.length === 0) {
    console.error("[ERROR] No configuration found. Provide projects.json or REPO_URL environment variable.");
    process.exit(1);
}

const INTERVAL_MS = (parseInt(process.env.INTERVAL_SECONDS) || 120) * 1000;
const HTTP_PORT = 80;
const BASE_WWW_DIR = '/var/www/html';

const app = express();

app.use(express.static(BASE_WWW_DIR));

app.use('/:project/:branch', (req, res, next) => {
    const { project, branch } = req.params;
    const branchDir = path.join(BASE_WWW_DIR, project, branch);
    const indexPath = path.join(branchDir, 'index.html');

    if (existsSync(branchDir) && existsSync(indexPath)) {
        res.sendFile(indexPath);
    } else {
        next();
    }
});

app.use((req, res) => {
    res.status(404).send('404 - Not Found');
});

app.listen(HTTP_PORT, () => {
    console.log(`[SERVER] Listening on port ${HTTP_PORT}`);
});

class DeployManager {
    constructor(config) {
        this.repoUrl = config.REPO_URL;
        this.projectName = this.repoUrl.split('/').pop().replace('.git', '');
        this.gitToken = config.GIT_TOKEN || '';
        this.branchRegex = config.BRANCH_REGEX ? new RegExp(config.BRANCH_REGEX) : null;

        this.authRepoUrl = (this.gitToken && this.repoUrl.startsWith('https://'))
            ? this.repoUrl.replace('https://', `https://${this.gitToken}@`)
            : this.repoUrl;

        this.workDir = `/tmp/workdir/${this.projectName}`;
        this.destDir = path.join(BASE_WWW_DIR, this.projectName);
        this.stateFile = path.join(this.destDir, 'state.json');
    }

    log(message) {
        const time = new Date().toLocaleTimeString('en-US', { hour12: false });
        console.log(`[${this.projectName}] [${time}] ${message}`);
    }

    sanitizeBranchName(branchName) {
        return branchName.toLowerCase().replace(/[^a-z0-9]/g, '-').replace(/^-|-$/g, '');
    }

    async loadState() {
        try {
            if (existsSync(this.stateFile)) {
                const data = await fs.readFile(this.stateFile, 'utf-8');
                return JSON.parse(data);
            }
        } catch (error) {}
        return {};
    }

    async saveState(state) {
        await fs.writeFile(this.stateFile, JSON.stringify(state, null, 2));
    }

    async initGit() {
        await fs.mkdir(this.workDir, { recursive: true });
        await fs.mkdir(this.destDir, { recursive: true });

        if (!existsSync(path.join(this.workDir, '.git'))) {
            this.log(`Initial git clone...`);
            await execAsync(`git clone "${this.authRepoUrl}" . --quiet`, { cwd: this.workDir });
        }
    }

    async getRemoteBranches() {
        await execAsync(`git fetch --all --prune --quiet`, { cwd: this.workDir });
        const { stdout } = await execAsync(`git branch -r | grep origin/ | grep -v HEAD`, { cwd: this.workDir });

        const branches = stdout.split('\n')
            .map(b => b.trim().replace('origin/', ''))
            .filter(b => b.length > 0);

        const branchHashes = {};
        for (const branch of branches) {
            const { stdout: hash } = await execAsync(`git rev-parse "origin/${branch}"`, { cwd: this.workDir });
            branchHashes[branch] = hash.trim();
        }
        return branchHashes;
    }

    async buildBranch(branch, safeBranch) {
        this.log(`Building branch: ${branch}`);

        try {
            await execAsync(`git clean -fdx && git reset --hard && git checkout -B "${branch}" "origin/${branch}" --quiet`, { cwd: this.workDir });

            if (!existsSync(path.join(this.workDir, 'package.json'))) {
                return false;
            }

            const hasPackageLock = existsSync(path.join(this.workDir, 'package-lock.json'));
            const installCmd = hasPackageLock ? 'npm ci --silent --prefer-offline' : 'npm install --silent --prefer-offline';

            await execAsync(installCmd, { cwd: this.workDir });

            const basePath = `/${this.projectName}/${safeBranch}/`;
            const env = {
                ...process.env,
                VITE_BASE_PATH: basePath,
                PUBLIC_URL: basePath
            };

            await execAsync(`npm run build -- --base="${basePath}"`, { cwd: this.workDir, env });

            const branchDestPath = path.join(this.destDir, safeBranch);

            await fs.rm(branchDestPath, { recursive: true, force: true });
            await fs.mkdir(branchDestPath, { recursive: true });
            await execAsync(`cp -a dist/* "${branchDestPath}/"`, { cwd: this.workDir });

            this.log(`Deployed ${branch} to ${basePath}`);
            return true;
        } catch (error) {
            this.log(`Build failed for ${branch}: ${error.message}`);
            return false;
        }
    }

    async cleanup(activeSafeBranches) {
        const dirs = await fs.readdir(this.destDir, { withFileTypes: true });
        for (const dirent of dirs) {
            if (dirent.isDirectory() && !activeSafeBranches.includes(dirent.name)) {
                await fs.rm(path.join(this.destDir, dirent.name), { recursive: true, force: true });
            }
        }
    }

    async generateDashboard(activeSafeBranches) {
        const indexPath = path.join(this.destDir, 'index.html');
        const jsonPath = path.join(this.destDir, 'branches.json');

        try {
            if (existsSync('/app/index.html')) {
                await fs.copyFile('/app/index.html', indexPath);
            }
        } catch (e) {}

        const branchesData = {
            base_path: `/${this.projectName}`,
            last_update: new Date().toISOString().replace('T', ' ').substring(0, 19),
            branches: activeSafeBranches.map(branch => ({
                name: branch,
                link: `/${this.projectName}/${branch}/`
            }))
        };

        await fs.writeFile(jsonPath, JSON.stringify(branchesData, null, 2));
    }

    async sync() {
        try {
            await this.initGit();
            const remoteBranches = await this.getRemoteBranches();
            const localState = await this.loadState();

            let stateChanged = false;
            const activeSafeBranches = [];

            for (const [branch, remoteHash] of Object.entries(remoteBranches)) {
                if (this.branchRegex && !this.branchRegex.test(branch)) {
                    continue;
                }

                const safeBranch = this.sanitizeBranchName(branch);
                activeSafeBranches.push(safeBranch);

                if (localState[safeBranch] !== remoteHash) {
                    this.log(`New commit on '${branch}' (${remoteHash})`);

                    localState[safeBranch] = remoteHash;
                    stateChanged = true;

                    await this.buildBranch(branch, safeBranch);
                }
            }

            await this.cleanup(activeSafeBranches);
            await this.generateDashboard(activeSafeBranches);

            if (stateChanged) {
                await this.saveState(localState);
            }

        } catch (error) {
            this.log(`Sync error: ${error.message}`);
        }
    }
}

const managers = projectsConfig.map(cfg => new DeployManager(cfg));

const syncAll = async () => {
    for (const manager of managers) {
        await manager.sync();
    }
};

console.log(`[SERVER] Started. Interval: ${INTERVAL_MS / 1000}s`);
syncAll();
setInterval(syncAll, INTERVAL_MS);