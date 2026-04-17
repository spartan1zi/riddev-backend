/** Pesewas: agreed worker amount, trust fee 5% on customer, commission from worker side */
export function computeFees(agreedWorkerPesewas: number, commissionBps: number): {
  trustFeePesewas: number;
  platformFeePesewas: number;
  workerPayoutPesewas: number;
  customerTotalPesewas: number;
} {
  const trustFeePesewas = Math.round((agreedWorkerPesewas * 500) / 10000);
  const platformFeePesewas = Math.round((agreedWorkerPesewas * commissionBps) / 10000);
  const workerPayoutPesewas = agreedWorkerPesewas - platformFeePesewas;
  const customerTotalPesewas = agreedWorkerPesewas + trustFeePesewas;
  return {
    trustFeePesewas,
    platformFeePesewas,
    workerPayoutPesewas,
    customerTotalPesewas,
  };
}
