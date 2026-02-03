import React, { useState } from 'react';
import { Terminal, Github, Smartphone, Download, Shield, Play, AlertCircle, CheckCircle2 } from 'lucide-react';
import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: (string | undefined | null | false)[]) {
    return twMerge(clsx(inputs));
}

export default function App() {
    const [formData, setFormData] = useState({
        rom_url: '',
        device_name: '',
        firmware_url: '',
        github_token: import.meta.env.VITE_GITHUB_TOKEN || ''
    });

    const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
    const [message, setMessage] = useState('');

    const REPO_OWNER = 'Jefino9488';
    const REPO_NAME = 'repack';
    const WORKFLOW_ID = 'repack.yml'; // Must match filename in .github/workflows/

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!formData.rom_url || !formData.device_name) {
            setStatus('error');
            setMessage('ROM URL and Device Name are required.');
            return;
        }

        if (!formData.github_token) {
            setStatus('error');
            setMessage('GitHub Token is required to trigger workflows. Enter one or set VITE_GITHUB_TOKEN.');
            return;
        }

        setStatus('loading');
        setMessage('Triggering build...');

        try {
            const response = await fetch(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/${WORKFLOW_ID}/dispatches`, {
                method: 'POST',
                headers: {
                    'Accept': 'application/vnd.github.v3+json',
                    'Authorization': `token ${formData.github_token}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    ref: 'main', // Or 'master' or the specific branch name. 'builder' in original repo, check later. Assumed 'main' or 'master' for new repo.
                    inputs: {
                        rom_url: formData.rom_url,
                        device_name: formData.device_name,
                        firmware_url: formData.firmware_url || ''
                    }
                })
            });

            if (response.status === 204) {
                setStatus('success');
                setMessage('Workflow triggered successfully! Check GitHub Actions tab.');
            } else {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.message || `Failed to trigger workflow (${response.status})`);
            }
        } catch (error: any) {
            console.error(error);
            setStatus('error');
            setMessage(error.message || 'An unexpected error occurred.');
        }
    };

    return (
        <div className="min-h-screen bg-cyber-dark text-gray-200 p-4 md:p-8 flex items-center justify-center font-sans relative overflow-hidden">
            {/* Background Elements */}
            <div className="absolute top-0 left-0 w-full h-full pointer-events-none overflow-hidden">
                <div className="absolute top-[-10%] left-[-10%] w-[50%] h-[50%] bg-cyber-primary/5 rounded-full blur-[100px]" />
                <div className="absolute bottom-[-10%] right-[-10%] w-[50%] h-[50%] bg-cyber-secondary/5 rounded-full blur-[100px]" />
            </div>

            <div className="w-full max-w-2xl relative z-10">
                <div className="mb-8 text-center space-y-2">
                    <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-cyber-panel border border-cyber-border shadow-[0_0_15px_rgba(0,229,255,0.1)] mb-4">
                        <Terminal className="w-8 h-8 text-cyber-primary" />
                    </div>
                    <h1 className="text-4xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-cyber-primary to-cyber-secondary filter drop-shadow-sm font-mono tracking-tight">
                        XAGA REPACKER
                    </h1>
                    <p className="text-cyber-muted text-sm uppercase tracking-widest">Fastboot ROM Builder</p>
                </div>

                <div className="bg-cyber-panel border border-cyber-border rounded-xl shadow-2xl overflow-hidden backdrop-blur-sm">
                    {/* Header Stripe */}
                    <div className="h-1 w-full bg-gradient-to-r from-cyber-primary via-purple-500 to-cyber-secondary" />

                    <div className="p-6 md:p-8 space-y-6">
                        <form onSubmit={handleSubmit} className="space-y-5">

                            {/* ROM URL */}
                            <div className="space-y-1">
                                <label className="flex items-center text-sm font-medium text-cyber-primary/90">
                                    <Download className="w-4 h-4 mr-2" />
                                    Recovery ROM Direct Link <span className="text-cyber-secondary ml-1">*</span>
                                </label>
                                <input
                                    type="url"
                                    placeholder="https://mirror.example.com/miui_...zip"
                                    className="w-full bg-cyber-dark border border-cyber-border rounded-lg px-4 py-3 text-sm focus:outline-none focus:border-cyber-primary focus:ring-1 focus:ring-cyber-primary transition-all placeholder-gray-700"
                                    value={formData.rom_url}
                                    onChange={e => setFormData({ ...formData, rom_url: e.target.value })}
                                    required
                                />
                            </div>

                            {/* Device Name */}
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
                                <div className="space-y-1">
                                    <label className="flex items-center text-sm font-medium text-cyber-primary/90">
                                        <Smartphone className="w-4 h-4 mr-2" />
                                        Device / Output Name <span className="text-cyber-secondary ml-1">*</span>
                                    </label>
                                    <input
                                        type="text"
                                        placeholder="e.g. spes"
                                        className="w-full bg-cyber-dark border border-cyber-border rounded-lg px-4 py-3 text-sm focus:outline-none focus:border-cyber-primary focus:ring-1 focus:ring-cyber-primary transition-all placeholder-gray-700"
                                        value={formData.device_name}
                                        onChange={e => setFormData({ ...formData, device_name: e.target.value })}
                                        required
                                    />
                                </div>

                                {/* Firmware URL */}
                                <div className="space-y-1">
                                    <label className="flex items-center text-sm font-medium text-gray-400">
                                        <Shield className="w-4 h-4 mr-2" />
                                        Firmware URL (Optional)
                                    </label>
                                    <input
                                        type="url"
                                        placeholder="https://..."
                                        className="w-full bg-cyber-dark border border-cyber-border rounded-lg px-4 py-3 text-sm focus:outline-none focus:border-cyber-primary focus:ring-1 focus:ring-cyber-primary transition-all placeholder-gray-700"
                                        value={formData.firmware_url}
                                        onChange={e => setFormData({ ...formData, firmware_url: e.target.value })}
                                    />
                                </div>
                            </div>

                            {/* GitHub Token */}
                            <div className="space-y-1 pt-4 border-t border-cyber-border/50">
                                <label className="flex items-center text-sm font-medium text-gray-400">
                                    <Github className="w-4 h-4 mr-2" />
                                    GitHub Token (PAT)
                                </label>
                                <p className="text-xs text-cyber-muted mb-2">Required to trigger workflow. Overrides env variable.</p>
                                <input
                                    type="password"
                                    placeholder="github_pat_..."
                                    className="w-full bg-cyber-dark border border-cyber-border rounded-lg px-4 py-3 text-sm focus:outline-none focus:border-cyber-primary focus:ring-1 focus:ring-cyber-primary transition-all placeholder-gray-700"
                                    value={formData.github_token}
                                    onChange={e => setFormData({ ...formData, github_token: e.target.value })}
                                />
                            </div>

                            {/* Status Message */}
                            {status !== 'idle' && (
                                <div className={cn(
                                    "p-4 rounded-lg flex items-start gap-3 text-sm animate-in fade-in slide-in-from-top-2",
                                    status === 'error' ? "bg-red-500/10 border border-red-500/30 text-red-400" :
                                        status === 'success' ? "bg-green-500/10 border border-green-500/30 text-green-400" :
                                            "bg-cyber-primary/10 border border-cyber-primary/30 text-cyber-primary"
                                )}>
                                    {status === 'error' ? <AlertCircle className="w-5 h-5 shrink-0" /> :
                                        status === 'success' ? <CheckCircle2 className="w-5 h-5 shrink-0" /> :
                                            <div className="w-5 h-5 border-2 border-current border-t-transparent rounded-full animate-spin shrink-0" />
                                    }
                                    <div>
                                        <p className="font-medium">{status === 'loading' ? 'Processing...' : status === 'success' ? 'Success' : 'Error'}</p>
                                        <p className="text-white/70">{message}</p>
                                    </div>
                                </div>
                            )}

                            {/* Submit Button */}
                            <button
                                type="submit"
                                disabled={status === 'loading'}
                                className="w-full bg-gradient-to-r from-cyber-primary to-blue-600 hover:to-blue-500 text-black font-bold py-4 rounded-lg flex items-center justify-center gap-2 transform transition-all active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed shadow-[0_0_20px_rgba(0,229,255,0.3)] hover:shadow-[0_0_30px_rgba(0,229,255,0.5)]"
                            >
                                <Play className="w-5 h-5 fill-black" />
                                TRIGGER BUILD
                            </button>
                        </form>
                    </div>

                    <div className="bg-cyber-dark/50 p-4 border-t border-cyber-border flex justify-between items-center text-xs text-cyber-muted">
                        <span>v1.0.0</span>
                        <span className="font-mono">REPACK // SYSTEM</span>
                    </div>
                </div>
            </div>
        </div>
    )
}
